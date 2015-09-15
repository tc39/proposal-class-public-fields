# ES Class Properties

This concept is comprised of two separate (but related) proposals: "class instance" property initializers and "class static" property intializers. "Instance" properties are set once per instiation of a class on the `this` value, and "static" properties are set on the class object itself.

## Proposal 1/2: Class Instance Properties

This is a proposal to include a declarative means of expressing instance properties on an ES class. These property declarations may include intializers, but are not required to do so.

The proposed syntax for this is as follows:

```javascript
class MyClass {
  myProp = 42;
  
  constructor() {
    console.log(this.myProp); // Prints '42'
  }
}
```

### Why?

##### Expressiveness & Boilerplate

The current idiomatic means of initializing a property on a class instance does not provide an expressively distinct way to "declare" them as part of the structure of a class. Specifically, in order to create a class property today one must assign to an expando on `this` in the constructor. This poses an inconvenience to tooling (and also sometimes humans) when trying to deduce the intended set of members for a class simply because there is no clear distinction between initialization logic and the intended shape of the class.

Additionally, because properties often need to be setup during class construction for object initialization, derived classes that wish to declare/initialize their own properties must implement some boilerplate to execute base class initialization first:

```javascript
class ReactCounter extends React.Component {
  constructor(props) { // boilerplate
    super(props); // boilerplate
    
    // Setup initial "state" property
    this.state = {
      count: 0
    };
  }
}
```

By allowing explicit and syntactically distinct instance property declarations, it becomes possible for tools and documentation to easily extract the intended shape of the class. Additionally it becomes possible for derived classes to specify non-constructor-dependent property initialization without having to explicitly intercept the constructor chain (write a constructor, call `super()`, etc).

Initialization situations like the following are common in many pervasive frameworks like React, Ember, Backbone, etc. as well as even just "vanilla" application code:

```javascript
class ReactCounter extends React.Component {
  // Freshly-built counters should always start at zero!
  state = {
    count: 0;
  };
}
```

Additionally, static analysis tools like Flow, TypeScript, ESLint, and many others can take advantage of the explicit declarations (along with additional metadata like typehints or JSDoc pragmas) to warn about typos or mistakes in code if the user declaratively calls out the shape of the class.

##### Decorators for Non-Method Class Members

In lockstep with the [sibling proposal for class-member decorators](https://github.com/wycats/javascript-decorators), declarative class properties also provide a syntactic (and semantic) space for specifying decorators on class properties. This opens up an expansive set of use cases for decorators within classes beyond what could otherwise only be applied to method members. Some examples include `@readonly` (for, say, specifying `writable:false` on the property descriptor), or `@hasMany` (for systems like Ember where the framework may generate a getter that does a batched fetch), etc.

##### Potential VM Warm-Up Optimizations

When properties are specified declaratively, VMs have an opportunity to generate best-effort member offsets earlier (similar to existing strategies like hidden classes).

### How?

##### Proposed Syntax

Instance property declarations may either specify an initializer or not:

```javascript
class ClassWithoutInits {
  myProp;
}

class ClassWithInits {
  myProp = 42;
}
```

##### Property Declarations Without Initializers

When no initializer is specified for a declared property, the property declaration will act as a no-op. This is useful for scenarios where initialization needs to happen somewhere other than in the initializer position (ex. If the property depends on constructor-injected data and thus needs to be initialized inside the construtor, or if the property is managed externally by something like a decorator or framework).

Additionally, it's sometimes useful for derived classes to "silently" specify a class property that may have been setup on a base class (either using or not using property declarations). For this reason, a declaration with no initializer should not attempt to overwrite data potentially written by a base class.

##### Property Declarations With Initializers

When a property with an initializer is specifed on a non-derived class (AKA a class without an `extends` clause), the initializers are declared and executed in the order they are specified in the class definition. Execution of the initializers happens during the internal "initialization" process that occurs immediately *before* entering the constructor.

When an initializer is specified on a derived class (AKA a class with an `extends` clause), the initializers are declared and executed in the order they are specified in the class definition. Execution of the initializers happens at the end of the internal "initialization" process that occurs while executing `super()` in the derived constructor. This means that if a derived constructor never calls `super()`, instance properties specified on the derived class will not be initialized since property initialization is considered a part of the [SuperCall Evaluation process](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-super-keyword-runtime-semantics-evaluation).

##### Property Declaration & Execution Process

The process of declaring a property happens at the time of [class definition evaluation](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-runtime-semantics-classdefinitionevaluation). The process for executing a property's initializer happens at class instantiation time and depends on wether the class is a "base" class (AKA has no `extends` clause) or is a "child" class (AKA has an `extends` clause). The differences between these two cases is described above in [Property Declarations Without Initializers](#property-declarations-without-initializers) and [Property Declarations With Initializers](#property-declarations-with-initializers).

The high level process for declaring class properties is as follows for each property in the order the properties are declared. (for sake of definition we assume a name for the class being defined is `DefinedClass`):

1. If the property name is computed, evaluate the computed property expression to a string to conclude the name of the property.
2. Create a function whose body simply executes the initializer expression and returns the result. This function's parent scope should be set to the scope of the class body. To be super clear: This scope should sit sibling to the scope of any of the class's method bodies.
3. If the `DefinedClass.prototype[Symbol.ClassProperties]` object is not already set, create and set it.
4. On the `DefinedClass.prototype[Symbol.ClassProperties]` object, store the function generated in step 2 under the key matching the name of the property being evaluated.

The purpose for generating and storing these "thunk" functions is a means of deferring the execution of the initialization expression until the class is constructed; Thus, the high level process for executing class property initializers is as follows -- once for each property in the order the properties are declared:

1. For each entry on `DefinedClass.prototype[Symbol.ClassProperties]`, call the value as a function with a `this` value equal to the `this` value of the object being constructed.
2. Define the result of the call in step 1 as a property on the `this` object with a key corresponding to the key of the `DefinedClass.prototype[Symbol.ClassProperties]` entry currently being evaluated. It should be defined with the following descriptor:

```javascript
{
  configurable: true,
  enumerable: true,
  writable: true,
  get: undefined,
  set: undefined,
}
```

## Proposal 2/2: Class "Static" Properties

(This is a proposal very much related to the former, but is much simpler in scope and is technically orthogonal -- so I've separated it for simplicity.)

This second proposal intends to include a declarative means of expressing "static" properties on an ES class. These property declarations may include intializers, but are not required to do so.

The proposed syntax for this is as follows:

```javascript
class MyClass {
  static myStaticProp = 42;
  
  constructor() {
    console.log(MyClass.myProp); // Prints '42'
  }
}
```

### Why?

Currently it's possible to express static methods on a class definition, but it is not possible to declaratively express static properties. As a result people generally have to assign static properties on a class after the class declaration -- which makes it very easy to miss the assignment as it does not appear as part of the definition.

### How?

Static property declarations are fairly straightforward in terms of semantics compared to their instance-property counter-parts. When a class definition is evaluated, the following set of operations is executed:

1. If the property name is computed, evaluate the computed property expression to a string to conclude the name of the property.
2. Create a function whose body simply executes the initializer expression and returns the result. This function's parent scope should be set to the scope of the class body. To be super clear: This scope should sit sibling to the scope of any of the class's method bodies.
3. If the `ClassDefinition[Symbol.ClassProperties]` object is not already set, create and set it.
4. On the `ClassDefinition[Symbol.ClassProperties]` object, store the function generated in step 2 under the key matching the same name of the property being evauated.
5. Call the function defined in step 2 with a `this` value equal to the `this` value of the object being constructed.
6. Define the result of the call in step 1 as a property on the `this` object with a key corresponding to the key of the `DefinedClass.prototype[Symbol.ClassProperties]` entry currently being evaluated. It should be defined with the following descriptor:

```javascript
{
  configurable: true,
  enumerable: true,
  writable: true,
  get: undefined,
  set: undefined,
}
```

Note that we store the static property thunk functions on `ClassDefinition[Symbol.ClassProperties]` for purposes of allowing userland introspection of declared properties on a class.

## Spec Text

\<\<TODO>>
