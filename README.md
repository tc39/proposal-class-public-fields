# ES Class Fields & Static Properties

This presents two related proposals: "class instance fields" and "class static properties". "Class instance fields" describe properties intended to exist on instances of a class (and may optionally include initializer expressions for said properties). "Class static properties" are declarative properties that exist on the class object itself (and may optionally include initializer expressions for said properties).

## Part 1: Class Instance Fields

The first part of this proposal is to include a means of declaring fields for instances of an ES class. These field declarations may include intializers, but are not required to do so.

The proposed syntax for this is as follows:

```javascript
class MyClass {
  myProp = 42;
  
  constructor() {
    console.log(this.myProp); // Prints '42'
  }
}
```

### How It Works

##### Proposed Syntax

Instance field declarations may either specify an initializer or not:

```javascript
class ClassWithoutInits {
  myProp;
}

class ClassWithInits {
  myProp = 42;
}
```

##### Instance Field Declaration Process

When an instance field is specified **with no initializer**, the presence of the field declaration will have the effect of doing `Object.defineProperty(this, propName, { [...] value: this.prop})` on the constructed object (potentially reading through a prototype chain on the RHS via \[\[Get]]). The ability to leave off an initializer is important for scenarios where initialization needs to happen somewhere other than in the declarative initialization position (ex. If the property depends on constructor-injected data and thus needs to be initialized inside the construtor, or if the property is managed externally by something like a decorator or framework). And the reason we copy the \[\[Get]] result into an own-property is to ensure that any changes to objects that sit in the prototype chain (such as, perhaps, a method by the same name) do not change the declared-field properties on the instance.

For example:

```javascript
class Base {
  initialized() { return 'base initialized'; }
  uninitialized() { return 'base uninitialized'; }
}

class Child extends Base {
  initialized = () => 'child initialized';
  uninitialized;
}

var child = new Child();
child.initialized(); // 'child initialized'
child.uninitialized(); // 'base uninitialized'

Base.prototype.initialized = () => 'new base initialized';
Base.prototype.uninitialized = () => 'new base uninitialized';

child.initialized(); // Remains 'child initialized'
child.uninitialized(); // Remains 'base uninitialized'
```

Additionally, it's sometimes useful for derived classes to "silently" specify a class field that may have been setup on a base class (perhaps using field declarations). For this reason, writing `null` or `undefined` and potentially overwriting data written by a parent class cannot happen.

When an instance field **with an initializer** is specifed on a **non-derived class (AKA a class without an `extends` clause)**, the list of fields (each comprised of a name and an initializer expression) are stored in a slot on the class object in the order they are specified in the class definition. Execution of the initializers happens during the internal "initialization" process that occurs immediately *before* entering the constructor.

When an instance field **with an initializer** is specified on a **derived class (AKA a class with an `extends` clause)**, the list of fields (each comprised of a name and an initializer expression) are stored in a slot on the class object in the order they are specified in the class definition. Execution of the initializers happens at the end of the internal "initialization" process that occurs while executing `super()` in the derived constructor. This means that if a derived constructor never calls `super()`, instance fields specified on the derived class will not be initialized since property initialization is considered a part of the [SuperCall Evaluation process](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-super-keyword-runtime-semantics-evaluation).

During the process of executing field initializers at construction time, field initializations happen **in the order the fields were declared on the class.**

The process of declaring instance fields on a class happens at the time of [class definition evaluation](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-runtime-semantics-classdefinitionevaluation). This process is roughly defined as follows for each field in the order the fields are declared:

1. Let _F_ be the class object being defined.
2. Let _fieldName_ be the result of evaluating the field name expression to a string (i.e. potentially a computed property).
2. If an initializer expression is present on the field declaration
  1. Let _fieldInitializerExpression_ be a thunk of the initializer expression.
4. Else,
  1. Let _fieldInitializerExpression_ be a thunk of the expression represented by \[\[Get]](_fieldName_, _this_)
5. Call _F_.\[\[SetClassInstanceField]](fieldName, fieldInitializerExpression) to store the field name + initializer on the constructor.

Note that the purpose for storing the initializer expressions as a thunk is to allow the deferred execution of the initialization expression until class construction time; Thus, 

##### Instance Field Initialization Process

The process for executing a field initializer happens at class instantiation time. The following describes the process for initializing each class field initializer (intended to run once for each field in the order they are declared):

1. Let _instance_ be the object being instantiated.
2. Let _fieldName_ be the string name for the current field (as stored in the slot on the constructor function).
3. Let _fieldInitializerExpression_ be the thunked initializer expression for the current field (as stored in the slot on the constructor function).
4. Let _initializerResult_ be the result of evaluating _fieldInitializerExpression_ with `this` equal to _instance_.
5. Let _propertyDescriptor_ be PropertyDescriptor{\[\[Value]]: _initializerResult_, \[\[Writable]]: true, \[\[Enumerable]]: true, \[\[Configurable]]: true}.
6. Call _instance_.\[\[DefineOwnProperty]](_fieldName_, _propertyDescriptor_).

### Why?

##### Expressiveness & Boilerplate

The current idiomatic means of initializing a property on a class instance does not provide an expressively distinct way to "declare" them as part of the structure of a class. One must assign to an expando property on `this` in the constructor -- or anywhere, really. This poses an inconvenience to tooling (and also often humans) when trying to deduce the *intended* set of members for a class simply because there is no clear distinction between initialization logic and the intended shape of the class.

Additionally, because instance-generated properties often need to be setup during class construction for object initialization, derived classes that wish to declare/initialize their own properties must implement some boilerplate to execute base class initialization first:

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

By allowing explicit and syntactically distinct field declarations it becomes possible for tools, documentation, and runtimes to easily extract the intended shape of a class and it's objects. Additionally it becomes possible for derived classes to specify non-constructor-dependent property initialization without having to explicitly intercept the constructor chain (write an override constructor, call `super()`, etc).

Initialization situations like the following are common in many pervasive frameworks like React, Ember, Backbone, etc. as well as "vanilla" application code:

```javascript
class ReactCounter extends React.Component {
  // Freshly-built counters should always start at zero!
  state = {
    count: 0
  };
}
```

Additionally, static analysis tools like Flow, TypeScript, ESLint, and many others can take advantage of the explicit declarations (along with additional metadata like typehints or JSDoc pragmas) to warn about typos or mistakes in code if the user declaratively calls out the shape of the class.

##### Decorators for Class Instance Fields

In lockstep with the [sibling proposal for class-member decorators](https://github.com/wycats/javascript-decorators), class instance fields must also provide a syntactic (and semantic) space for specifying decorators on said fields. This opens up an expansive set of use cases for decorators within classes beyond what could otherwise only be applied to method members. Some examples include `@readonly` (for, say, specifying `writable:false` on the property descriptor), or `@hasMany` (for systems like Ember where the framework may generate a getter that does a batched fetch), etc.

##### Potential VM Warm-Up Optimizations

When class instance fields are specified declaratively, VMs have an opportunity to generate best-effort optimizations earlier (at compile time) similar to existing strategies like hidden classes.

## Part 2: Class Static Properties

(This is very much related to the former section, but is much simpler in scope and is technically orthogonal -- so I've separated it for simplicity)

This second part of the proposal intends to include a declarative means of expressing "static" properties on an ES class object. These property declarations may include intializers, but are not required to do so.

The proposed syntax for this is as follows:

```javascript
class MyClass {
  static myStaticProp = 42;
  
  constructor() {
    console.log(MyClass.myStaticProp); // Prints '42'
  }
}
```

### How It Works

Static property declarations are fairly straightforward in terms of semantics compared to their instance-property counter-parts. When a class definition is evaluated, the following set of operations is executed:

1. Let _F_ be the class object being defined.
2. Let _propName_ be the result of executing [PropName](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-object-initializer-static-semantics-propname) of the _PropertyName_ of the static property declaration
3. If an initializer expression is present
  1. Let _initializerValue_ be the result of evaluating the initializer expression.
4. Else,
  1. Let _initializerValue_ be the result of \[\[Get]](_propName_, _F_)
5. Let _propertyDescriptor_ be PropertyDescriptor{\[\[Value]]: _initializerValue_, \[\[Writable]]: true, \[\[Enumerable]]: true, \[\[Configurable]]: true}.
6. Call _F_.\[\[DefineOwnProperty]](_propName_, _propertyDescriptor_).

### Why?

Currently it's possible to express static methods on a class definition, but it is not possible to declaratively express static properties. As a result people generally have to assign static properties on a class after the class declaration -- which makes it very easy to miss the assignment as it does not appear as part of the definition.

## Spec Text

(TODO: Spec text is outdated and is pending updates to changes that were made since the September2015 TC39 meeting and are already reflected in the above abstracts)

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

##### [14.5.14 Runtime Semantics: ClassDefinitionEvaluation](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-runtime-semantics-classdefinitionevaluation)

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
    1. **Let _initFunc_ be null**
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

##### [9.2.2 \[\[Construct\]\] ( argumentsList, newTarget ) ](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-ecmascript-function-objects-construct-argumentslist-newtarget)

The [[Construct]] internal method for an ECMAScript Function object _F_ is called with parameters _argumentsList_ and _newTarget_. _argumentsList_ is a possibly empty List of ECMAScript language values. The following steps are taken:

1. Assert: _F_ is an ECMAScript function object.
2. Assert: Type(_newTarget_) is Object.
3. Let _callerContext_ be the running execution context.
4. Let _kind_ be _F_’s [[ConstructorKind]] internal slot.
5. If _kind_ is "base", then
  1. Let _thisArgument_ be OrdinaryCreateFromConstructor(_newTarget_, "%ObjectPrototype%").
  2. ReturnIfAbrupt(_thisArgument_).
6. Let _calleeContext_ be PrepareForOrdinaryCall(_F_, _newTarget_).
7. Assert: _calleeContext_ is now the running execution context.\
8. If _kind_ is "base", then
  1. **TODO: Let _propInits_ be the result of GetClassPropertyStore of _F_.prototype**.
  2. **TODO: For each _propInitKeyValuePair_ from _propInits_**.
    1. **Let _propName_ be the first element of _propInitKeyValuePair_**
    2. **Let _propInitFunc_ be the second element of _propInitKeyValuePair_**
    2. **If _propInitFunc_ is not `null`, then**
      1. **TODO: Let _propValue_ be the result of executing _propInitFunc_ with a `this` of _thisArgument_.**
      2. **TODO: Let _success_ be the result of \[\[Set]](_propName_, _propValue_, _thisArgument_).**
      3. **TODO: ReturnIfArupt(_success_)**
  2. Perform OrdinaryCallBindThis(_F_, _calleeContext_, _thisArgument_).
9. Let _constructorEnv_ be the LexicalEnvironment of _calleeContext_.
10. Let _envRec_ be _constructorEnv_’s environment record.
11. Let _result_ be OrdinaryCallEvaluateBody(_F_, _argumentsList_).
12. Remove _calleeContext_ from the execution context stack and restore _callerContext_ as the running execution context.
13. If _result_.[[type]] is return, then
  1. If Type(_result_.[[value]]) is Object, return NormalCompletion(_result_.[[value]]).
  2. If _kind_ is "base", return NormalCompletion(_thisArgument_).
  3. If _result_.[[value]] is not undefined, throw a TypeError exception.
14. Else, ReturnIfAbrupt(_result_).
15. Return _envRec_.GetThisBinding().

##### [12.3.5.1 Runtime Semantics: Evaluation (SuperCall)](http://www.ecma-international.org/ecma-262/6.0/index.html#sec-super-keyword-runtime-semantics-evaluation)

_SuperCall_ : `super` _Arguments_

1. Let _newTarget_ be GetNewTarget().
2. If _newTarget_ is undefined, throw a ReferenceError exception.
3. Let _func_ be GetSuperConstructor().
4. ReturnIfAbrupt(_func_).
5. Let _argList_ be ArgumentListEvaluation of Arguments.
6. ReturnIfAbrupt(_argList_).
7. **Let _constructResult_ be Construct(_func_, _argList_, _newTarget_).**
8. ReturnIfAbrupt(_constructResult_).
9. Let _thisER_ be GetThisEnvironment( ).
10. **Let _bindThisResult_ _thisER_.BindThisValue(_constructResult_).**
11. **TODO: Let _propInits_ be the result of GetClassPropertyStore of _thisER_.[[FunctionObject]].**
12. **TODO: For each _propInitKeyValuePair_ from _propInits_**.
  1. **Let _propName_ be the first element of _propInitKeyValuePair_**
  2. **Let _propInitFunc_ be the second element of _propInitKeyValuePair_**
  3. **If _propInitFunc_ is not `null`, then**
    1. **TODO: Let _propValue_ be the result of executing _propInitFunc_ with a `this` of _thisArgument_.**
    2. **TODO: Let _success_ be the result of \[\[Set]](_propName_, _propValue_, _thisArgument_).**
    3. **TODO: ReturnIfArupt(_success_)**
13. **Return _bindThisResult_**
