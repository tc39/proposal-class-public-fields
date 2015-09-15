# ES Class Properties

This presents two related proposals: "class instance" property initializers and "class static" property intializers. "Instance" properties exist once per instiation of a class on the `this` value, and "static" properties exist on the class object itself.

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

The current idiomatic means of initializing a property on a class instance does not provide an expressively distinct way to "declare" them as part of the structure of a class. In order to create a class property today one must assign to an expando property on `this` in the constructor -- or anywhere, really. This poses an inconvenience to tooling (and also sometimes humans) when trying to deduce the *intended* set of members for a class simply because there is no clear distinction between initialization logic and the intended shape of the class.

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

By allowing explicit and syntactically distinct property declarations, it becomes possible for tools and documentation to easily extract the intended shape of a class and it's objects. Additionally it becomes possible for derived classes to specify non-constructor-dependent property initialization without having to explicitly intercept the constructor chain (write a constructor, call `super()`, etc).

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

##### Instance Property Declarations Without Initializers

When no initializer is specified for a declared property, the act of executing a property initializer will simply be a no-op. This is useful for scenarios where initialization needs to happen somewhere other than in the declarative init position (ex. If the property depends on constructor-injected data and thus needs to be initialized inside the construtor, or if the property is managed externally by something like a decorator or framework).

Additionally, it's sometimes useful for derived classes to "silently" specify a class property that may have been setup on a base class (either using or not using property declarations). For this reason, a declaration with no initializer should not attempt to overwrite data potentially written by a base class.

##### Instance Property Declarations With Initializers

When a property with an initializer is specifed on a **non-derived class (AKA a class without an `extends` clause)**, the initializers are declared and executed in the order they are specified in the class definition. Execution of the initializers happens during the internal "initialization" process that occurs immediately *before* entering the constructor.

When an initializer is specified on a **derived class (AKA a class with an `extends` clause)**, the initializers are declared and executed in the order they are specified in the class definition. Execution of the initializers happens at the end of the internal "initialization" process that occurs while executing `super()` in the derived constructor. This means that if a derived constructor never calls `super()`, instance properties specified on the derived class will not be initialized since property initialization is considered a part of the [SuperCall Evaluation process](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-super-keyword-runtime-semantics-evaluation).

##### Instance Property Declaration Process

The process of declaring a property happens at the time of [class definition evaluation](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-runtime-semantics-classdefinitionevaluation). This process is roughly defined as follows for each property in the order the properties are declared. (for sake of definition we assume a name for the class being defined is `DefinedClass`):

1. If the property name is computed, evaluate the computed property expression to a string to conclude the name of the property.
2. Create a function whose body simply executes the initializer expression and returns the result. This function's parent scope should be set to the scope of the class body. To be super clear: This scope should sit sibling to the scope of any of the class's method bodies.
3. If the `DefinedClass.prototype[Symbol.ClassProperties]` object is not already set, create and set it.
4. On the `DefinedClass.prototype[Symbol.ClassProperties]` object, store the function generated in step 2 under the key matching the name of the property being evaluated.

The purpose for generating and storing these "thunk" functions is a means of deferring the execution of the initialization expression until the class is constructed; Thus, 

##### Instance Property Initialization Process

The process for executing a property initializers happens at class instantiation time and depends on wether the class is a "base" class (AKA has no `extends` clause) or is a "derived" class (AKA has an `extends` clause). The differences between these two cases is described above in [Property Declarations Without Initializers](#property-declarations-without-initializers) and [Property Declarations With Initializers](#property-declarations-with-initializers). The following describes the process for initializing each class property initializer (intended to run once for each property in the order the properties are declared):

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
6. Define the result of the call in step 5 as a property on the `this` object with a key corresponding to the name of the property currently being evaluated. It should be defined with the following descriptor:

```javascript
{
  configurable: true,
  enumerable: true,
  writable: true,
  get: undefined,
  set: undefined,
}
```

Note that we store the static property thunk functions on `ClassDefinition[Symbol.ClassProperties]` for purposes of userland reflection on how the class was declared.

## Spec Text

##### [14.5 Class Definitions](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-class-definitions)

```
ClassPropertyInitializer : 
  PropertyName ;
  PropertyName = AssignmentExpression ;

ClassElement :
  MethodDefinition
  static MethodDefinition
  ClassPropertyInitializer
  static _ClassPropertyInitializer
  ;
```

##### *(new)* 14.5.x Static Semantics: GetDeclaredClassProperties

_ClassElementList_ : _ClassElement_

1. If _ClassElement_ is the production _ClassElement_ : _ClassPropertyInitializer_, return a List containing _ClassElement_.
2. If _ClassElement_ is the production _ClassElement_ : `static` _ClassPropertyInitializer_, return a list containing _ClassElement_.
3. Else return a new empty List.

_ClassElementList_ : _ClassElementList_ _ClassElement_

1. Let _list_ be PropertyInitializerList of _ClassElementList_
2. If _ClassElement_ is the production _ClassElement_ : _ClassPropertyInitializer_, append _ClassElement_ to the end of _list_.
3. If _ClassElement_ is the production _ClassElement_ : `static` _ClassPropertyInitializer_, append _ClassElement_ to the end of _list_.
4. Return _list_.

#### [14.5.14 Runtime Semantics: ClassDefinitionEvaluation](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-runtime-semantics-classdefinitionevaluation)

1. Let _lex_ be the LexicalEnvironment of the running execution context.
2. Let _classScope_ be NewDeclarativeEnvironment(_lex_).
3. Let _classScopeEnvRec_ be _classScope_’s environment record.
4. If _className_ is not undefined, then
    1. Perform _classScopeEnvRec_.CreateImmutableBinding(_className_, true).
5. If _ClassHeritage_<sub>opt</sub> is not present, then
    1. Let _protoParent_ be the intrinsic object %ObjectPrototype%.
    2. Let _constructorParent_ be the intrinsic object %FunctionPrototype%.
6. Else
    1. Set the running execution context’s LexicalEnvironment to _classScope_.
    2. Let _superclass_ be the result of evaluating _ClassHeritage_.
    3. Set the running execution context’s LexicalEnvironment to _lex_.
    4. ReturnIfAbrupt(_superclass_).
    5. If _superclass_ is null, then
      1. Let _protoParent_ be null.
      2. Let _constructorParent_ be the intrinsic object %FunctionPrototype%.
    6. Else if IsConstructor(_superclass_) is false, throw a TypeError exception.
    7. Else
      1. If _superclass_ has a [[FunctionKind]] internal slot whose value is "generator", throw a TypeError exception.
      2. Let _protoParent_ be Get(superclass, "prototype").
      3. ReturnIfAbrupt(_protoParent_).
      4. If Type(_protoParent_) is neither Object nor Null, throw a TypeError exception.
      5. Let _constructorParent_ be _superclass_.
7. Let _proto_ be ObjectCreate(_protoParent_).
8. If _ClassBody_<sub>opt</sub> is not present, let _constructor_ be empty.
9. Else, let _constructor_ be ConstructorMethod of _ClassBody_.
10. If _constructor_ is empty, then,
  1. If _ClassHeritage_<sub>opt</sub> is present, then
    1. Let _constructor_ be the result of parsing the String "constructor(... args){ super (...args);}" using the syntactic grammar with the goal symbol _MethodDefinition_.
  2. Else,
    1. Let _constructor_ be the result of parsing the String "constructor( ){ }" using the syntactic grammar with the goal symbol _MethodDefinition_.
11. Set the running execution context’s LexicalEnvironment to _classScope_.
12. Let _constructorInfo_ be the result of performing DefineMethod for _constructor_ with arguments _proto_ and _constructorParent_ as the optional _functionPrototype_ argument.
13. Assert: _constructorInfo_ is not an abrupt completion.
14. Let _F_ be _constructorInfo_.[[closure]]
15. If _ClassHeritage_<sub>opt</sub> is present, set _F_’s [[ConstructorKind]] internal slot to "derived".
16. Perform MakeConstructor(_F_, false, _proto_).
17. Perform MakeClassConstructor(_F_).
18. Perform CreateMethodProperty(_proto_, "constructor", _F_).
19. If _ClassBody_<sub>opt</sub> is not present, let _methods_ be a new empty List.
20. Else, let _methods_ be NonConstructorMethodDefinitions of _ClassBody_.
21. For each _ClassElement_ _m_ in order from _methods_
  1. If IsStatic of _m_ is false, then
    1. Let _status_ be the result of performing PropertyDefinitionEvaluation for _m_ with arguments _proto_ and false.
  2. Else,
    1. Let _status_ be the result of performing PropertyDefinitionEvaluation for _m_ with arguments _F_ and false.
  3. If _status_ is an abrupt completion, then
    1. Set the running execution context’s LexicalEnvironment to _lex_.
    2. Return _status_.
22. **If _ClassBody_<sub>opt</sub> is not present, let _propertyDecls_ be a new empty List.**
23. **Else, let _propertyDecls_ be GetDeclaredClassProperties of _ClassBody_.**
24. **For each _ClassElement_ _i_ in order from _propertyDecls_**
  1. **let _propName_ be the result of performing PropName of _i_**
  2. **TODO: If HasRHSExpression of _i_, then**
    1. **TODO: Let _initFunc_ be a function with an outer environment set to that of the class body that returns the result of executing the RHS expression**
  3. **Else,**
    1. **TODO: Let _initFunc_ be null**
  4. **If IsStatic of _i_ is false, then**
    1. **TODO: Let _propertyStore_ be GetClassPropertyStore of _proto_**
    2. **TODO: Object.defineProperty(_propertyStore_, _propName_, {configurable: true, enumerable: true, writable: true, value: _initFunc_})**
  5. **Else,**
    1. **TODO: Let _propertyStore_ be GetClassPropertyStore of _F_**
    2. **TODO: Object.defineProperty(_propertyStore_, _propName_, {configurable: true, enumerable: true, writable: true, value: _initFunc_})**
    3. **TODO: If HasRHSInitializer of _i_ is true, then**
      1. **Let _propValue_ be the result of calling _initFunc_**
      2. **TODO: Object.defineProperty(_F_, _propName_, {configurable: true, enumerable: true, writable: true, value: _propValue})**
25. Set the running execution context’s LexicalEnvironment to _lex_.
26. If _className_ is not undefined, then
  1. Perform _classScopeEnvRec_.InitializeBinding(_className_, _F_).
27. Return _F_.
