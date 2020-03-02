+++
title = "Unity gamedev: You are wrong about Dependency Injection"
date = 2020-02-27
draft = false
tags = ["unity", "programming", "rant"]
+++

*Unity in this post refer to the game engine, not the Microsoft framework, nor the DWM.*

The title might have make you feel angry, which is exactly what I feel when googled: "unity engine dependency injection". 

The every single link on the 1st page, except the pdf one which I skipped, is either full of straight-up false information about DI, or kind of correct but completely miss the main point.


## Common Misconceptions
### Misconception #1: It too complex, I don't need something to auto connect dependencies for me, Reflection bad,...
The biggest misconception about DI stem from the fact that people are confusing DI for one of the DI Framework. You know the type: phone book-sized documentation, frequent name dropping (IoC, SOLID, ...).

Now, these frameworks have their use, but as they're usually the top results on Google, they also scare away many beginners from what is an extremely simple and useful design pattern.

**> *You don't need any framework to use DI, and it'll be a lot simpler without them.***

Because of this confusion, many believe the purpose of DI is to avoid passing dependencies around. Instead, you conjure them by marking stuff with attributes, and they will be magically summoned by the dark power of Reflection.

**> *Dependency Injection have nothing to do with NOT passing thing around. It's the complete opposite.***

**> *Dependency Injection have nothing to do with Reflection***. It does not slow your code down. Unless you writing for an ATTiny where extra jump to subroutine matter. Also Reflection probably won't slow your game down either, unless you use them every frame. It one of those strangely popular cargo-cult.

### Misconception #2: DI is for unit testing

By using DI, you also have the ability to swap out dependencies of a class without modifying it. 

This is very useful when you want to do unit test, and is a big advantage of DI. However, ***being able to swap dependencies is a happy side-effect***, but it not the main point.

If you don't do unit testing, then first, you will never hear the end of it from people who do test, they believe it to be the second coming of Christ (not without reason). And second, you will still reap plenty of benefit from using DI.

### Almost Misconception #3: Unity Editor is a dependency injector

This one is kind of true. Unity Editor is indeed a dependency injector. It allow you to inject stuff into other stuff by dragging and dropping. This is very useful when you work with non-technical designer, and sometime it actually is enough.

Other time, you want to have dependencies on things that isn't an Unity Object.

Or maybe you want thing that are spawned at runtime to reference to thing that also spawned at runtime.

Or maybe you simply forgot to drag the right thing in the right place. The bigger you project grow, the more likely that this will happen.

## So what is Dependency Injection, and why do I want to use it?

Let say you want to let players select items in your games:

``` csharp
interface ISelector {
	void UpdatePosition(Vector2 newPosition);
	GameObject[] GetSelected();
}

ISelector selector;

void Start()
{
	selector = new SomeSelector();
}

void OnDrag(PointerEventData pointer)
{
	selector.UpdatePosition(pointer.position);
	selected = selector.GetSelected();
}
```

You implement `SomeSelector` as a "normal" C# class - not a MonoBehaviour - because it just logic and have nothing to do with Unity. It get the list of items to select from ItemManager, which is a Singleton.

`Error: NullReferenceException: player...`

Right, ItemManager need reference to Players. As Players are spawned at runtime, you forgot about it - it not like there is an empty slot on the ItemManager inspector to remind you. Just create the PlayerSpawner then.

`Error: NullReferenceException: inventoryPanel...`

What? Ah, Players also need Inventory to store the items they picked up. You haven't write the code to pickup item yet, so you think you can do it later. But no, ItemManager want to do something with them in `Awake`.

The Inventory need reference to the `inventoryPanel` to display what it contain. You have to remember to create one and put it in the right inspector slot.

This is a contrive example I made up on the spot; you could have avoid some of these problem by with a better design. However, if you have worked enough with Unity, you probably ran into these `NullReferenceException` a lot.

Most of the time, these errors come from objects being created or methods being executed in the wrong order. They're difficult to track down, because they only show up when the reference being used, not when they're created/assigned. It usually take a lot of time to track down these error, and it requires deep knowledge of the codebase.

You can remember the necessary details, like in the example above, if you just wrote Player and Inventory last week. But what about a year down the line? What about when someone else work on your project? Maybe a new team members, or a programmer from another studio that was hired to port your game to other platforms. They'll either have to dig through thousands of lines of code, or waste time communicating back and forth.

### Why does this happen?

The reason that these `NullReferenceException` happen is, most likely, because your variable are not properly initialize. Either you forgot to, or they're initialized in the wrong order.

When you use global variables, this happen a lot. You can change a global from anywhere, at anytime, so there is no guarantee that what you need will be where you expect it, when you need it. 

Because of this, when you look at a class, you have no idea what are it's dependencies, it can depend on every classes for all you know. Use of global variable obscure all dependencies.

Singleton are the herald of global variables. When you use a Singleton, you're not just using 1 global variable. You also make everything referenced by the Singleton, and anything referenced by those references and so on, global.

### Dependency Injection to the rescue

Here how you can implement DI for the example above:

``` csharp
// SomeSelector.cs
public SomeSelector(List<Item> itemsToSelect){}

// Some where else
public GameObject inventoryPanel;

var inventory   = new Inventory(inventoryPanel, ...);
var players     = new []{new Players(inventory)};
var itemManager = new ItemManager(players, ...);
var selector    = new SomeSelector(itemManager.itemList);
```

Basically, there're just 2 things to do:
 - Define what a class need, using constructor arguments.
 - Pass in (inject) these things when an instance of the class is constructed.

As you can see, there is no way for you to create `SomeSelector` without having the list of items to select, which have to come from `ItemManager`. In turn, `ItemManager` cannot be created without the list of `Player`s, and so on.

Not only that, there is no way for you to mess up the ordering. In order to create a Player, you need to provide it with an Inventory. There is no way to create the Inventory after the Player, so the Player can be sure that they always have an Inventory when they need it.

| What Dependency Injection do, is forcing you to be explicit about your dependencies |
| ----------------------------------------------------------------------------------- |

<br/>

Unfortunately, the code above probably can't be used most of the time in Unity. You need MonoBehaviour in Unity, and you can't use constructor of a MonoBehaviour. This is what I usually have to do to work around it:

``` csharp
class Players : MonoBehaviour{
	void Init(Inventory inventory, ...) {};
}

...
player = Instantiate(playerPrefab);
player.Init(inventory, ...)
```

We'll need 2 line to create and initialize an object. We have to remember to always call `Init`, and can't have the compiler yelling at us when we forget to pass in the dependencies. This is ugly, I have no better solution for this, and would love to hear if you have one. That said, I believe this to be the better long term solution than the invisible web that is Singleton.

## Common Concern

### What if my class have hundreds of dependencies? I have to have hundreds of arguments for my constructor/Init method?

You should never have hundreds of dependencies for a class. Instead you should split it up to multiple smaller classes, initialize those smaller class and pass the initialized instance into the big class. This is called Inversion of Control (IoC).

For example, you Player can walk, run, make sound, attack, pick thing up, ... But it do not need the reference to everything that are needed to all of these activity. 

Instead, you have separated class to handle each activity. For example, `PlayerAnimation`, which is initialized with AnimationClip and what not, then pass it to the `Player`. When `PlayerAnimation` need to talk to others, say `PlayerMovement`, they can do so through `Player`.

A common design would be for `Player` to hold its states, such as walking or running. Some class would write to these states, such as `PlayerInput` or `PlayerMovementImpairingEffect`. `PlayerAnimation` and `PlayerMovement` can both read from these states.

### What if I need an object in many places, do I have to pass it everywhere?

Most of the time, yes. Remember that by not passing thing around, you do not eliminate the need to pass thing around, you can only hide it.

Some of the time, Singleton can be a suitable choice. Yes, Singleton is not the root of all evil, nor DI is a silver bullet. As with everything in engineering, there always a trade off. You can use Singleton is if the class should logically have only one instance, and preferably if everything it expose is read-only. 

One example is in Google ARCore SDK: they use Singleton to provide the AR background, which is readonly, and logically 2 background cannot make sense. You can have 100 phone cameras, 4 phone display, the background might not be a 2D texture but a 3D point cloud, but there just can't be 2 background.

In any case, you can use whatever you want. I'm here to help you make informed decision, not be your mom.