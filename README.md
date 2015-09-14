# ES Class Properties

This concept is comprised of two separate (but related) proposals: "class instance" property initializers and "class static" property intializers.

## Proposal 1/2: ES Class Instance Properties

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

Additionally, static analysis tools like Flow, TypeScript, ESLint, and likely many others can take advantage of the explicit declarations (along with additional metadata like typehints or JSDoc pragmas) to warn about typos or mistakes in code if the user declaratively calls out the shape of the class.

##### Decorators for Non-Method Class Members

In lockstep with the [sibling proposal for class-member decorators](https://github.com/wycats/javascript-decorators), declarative class properties also provide a syntactic (and semantic) space for specifying decorators on class properties. This opens up an expansive set of use cases for decorators within classes beyond what could otherwise only be applied to method members. Some examples include `@readonly` (for, say, specifying `writable:false` on the property descriptor), or `@hasMany` (for systems like Ember where the framework may generate a getter that does a batched fetch), etc.

##### Potential VM Warm-Up Optimizations

When properties are specified declaratively, VMs have an opportunity to generate best-effort member offsets earlier (similar to existing strategies like hidden classes).

### How?

<<TODO>>

## Proposal 2/2: ES Class "Static" Properties

This is a proposal very much related to the former, but is much simpler in scope (and thus is separated into a separate proposal for sake of simplicity). This proposal intends to include a declarative means of expressing "static" properties on an ES class. These property declarations may include intializers, but are not required to do so.

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

<<TODO>>

### How?

<<TODO>>
