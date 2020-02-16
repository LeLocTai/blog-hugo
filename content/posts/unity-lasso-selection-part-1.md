+++
title = 'Unity Lasso Selection - Part 1: Building the foundation'
date = 2020-02-14
draft = true
tags = ["Unity", "Programming"]
videos = ["https://giant.gfycat.com/SparseFormalElkhound.mp4"]
+++

{{<gfycat SparseFormalElkhound controls requestautoplay muted loop>}}

## Introduction

This first post go through the process of designing and building all the infrastructure needed for the lasso selection system in Unity Engine, including some tips for managing dependency between Unity scripts.

While this seem mundane, a good design is extremely important for any system. Well designed system lets you extend them without tearing thing apart. It's easy to test, so you have confident that your new feature doesn't break any things. It's portable, so we can pull it from one project and plug it into another, without having to carry over a bunch of unrelated stuffs, and having to do unnecessary setup work.

This post, of course, will not cover everything you need to know to design a good system. But I'm a firm believer in the one-step-at-a-time approach to learning. If you going to get 1 thing out of this post, it is that dependency injection is easy, stop using singleton everywhere, especially if you're making tutorial for beginner ..cough..

If you're only interested in the lasso selection algorithm, it'll be in the next part. If you just want something you can use, the Github link is below.

Note that this series is only mean to explain the interesting parts of the project, not a step by step tutorial, so if you just use the code here, it probably will not run. The full codebase is available at https://github.com/LeLocTai/unity-objects-selections.

 <!--more--> 

## C# Quick Guide

This section outline some non-basic C# features that going to be used in this post. If you're familiar with the language, feel free to skip to the next section.

### Interface
``` csharp
public interface ISelectable {}
```

Interfaces let you define a list of features a class have, so many different class can be treated the same way. For example, the `IEnumerable` interface is implemented by both Array and Queue, so you if have a function that take an `IEnumerable` as parameter, you can pass in an Array or a Queue or something else, and the function still treat them the same way.

The convention in C# is to name interfaces with a leading `I`, in case you're confused by the name like me.

``` csharp
void GetSelected(IEnumerable<ISelectable> selectables)
{
	foreach (var selectable in selectables)
	{
		...
	}
}
```

### Event and delegate
C# events let you subscribe to them with delegates, which is just function you can pass around. Invoke the event will call all the delegate that has been subcribed to it.
``` csharp
public event Action selected;

selected += () => log("selected"); //subcribe with an anonymous function

selected?.Invoke(); //invoke. the ?. mean only call Invoke() if the event is not null.
```

Event can be subcribe to with a delegate, which is a function-as-a-variable. In this case, we uses the premade delegate type `Action`, which is a function that take nothing and return nothing.

## Selector and Selectable

Our system need only 2 interfaces:
 - **Selectable** that can be selected. I defines the as a list of points/vertices. If a certain percentage of these vertices is selected then the whole thing is selected.
 - **Selector**, which when given a list of selectables, produce a subset of them that is selected.

Using interfaces make it easy to swap out implementation without changing the users. So if we want to create a rectangle selection method, or if we want to make selectables from 2D Sprite, we don't have to touch anything unrelated - just implement the right interface.

### Selectable
The actual `Selectable` is a bit more complicated:
<div class="code-block">

``` csharp
public interface ISelectable
{
	IEnumerable<Vector3> Vertices            { get; }
	IEnumerable<Vector2> VerticesScreenSpace { get; }
```
Since most form of selection are done in screen space, we should cache the screen-space position of the vertices to avoid having to do the conversion everytime, as that would requires a relatively expensive matrix multiplication. If either screen-space or world-space position are not going to be used, the implementation can just return empty.
``` csharp
	int VerticesSelectedThreshold { get; }
```
We want to be able to select a shape, even if our lasso not fully cover the shape. We need to provide a number of vertices for the shape to be consider selected. This is a terrible name btw, suggestions are welcome.
``` csharp
	void InvalidateScreenPosition(Func<Vector3, Vector2> worldToScreenPoint);
```
We expect the camera to changes, so we need a way to notify the selectable to update it screenspace position.
``` csharp
	void OnSelected();
	void OnDeselected();
```
I also add 2 event invokers, so each selectable can be notified when they're selected or deselected. Implementer can choose to implement these with C# event for speed, or with UnityEvent for fancy editor.
``` csharp
}
```
</div>

### Selector
`Selector` is mostly straight forward.
``` csharp
public interface ISelector
{
	int GetSelected(IEnumerable<ISelectable> selectables, ICollection<ISelectable> result);
}
```

Instead of returning a collection, we return the amount of item selected, and add to the provided ICollection instead. This help us avoid allocating a new collection object every time we need selecting, which is every 16.(6)ms for the example above. Too frequent allocations will cause lag spike when the garbage collector run.

<details>
<summary>Speaking of allocation...</summary>

Using `IEnumerable` for selectables have an unfortunate consequence: the runtime will always allocate an `IEnumerator` object on the heap when we want to loop through the parameter. Normally, generic collections such as List implement `IEnumerable.GetEnumerator()` with a struct, which will allocate on the stack and not be handled by the garbage collector.

In this case, I choose to trade the slight sustained performance gain for more flexible code.

</details>

### Lasso Selector

Our Lasso Selector will be an implementation of the Selector interface.

A Lasso is essentially a polygon. So the lasso selector should store a list of vertices that define it. We can expose these vertices as readonly so later we can have another class that draw the lasso. 

<div class="code-block">

``` csharp
public class LassoSelector : ISelector
{
	readonly List<Vector2> vertices = new List<Vector2>();
	public List<Vector2> Vertices => vertices;
```
Note that both the readonly keyword and the lack of setter do not prevent other from modify the `vertices` List, as the variable itself is just a reference to the actual data. The proper way to implement readonly List is to make the property private, and create a public method that expose a way to access the List. I'm too lazy for that.
``` csharp
	public void ExtendLasso(Vector2 newPoint)
	{
		Vertices.Add(newPoint);
	}

	public void Reset()
	{
		Vertices.Clear();
	}
```
A few method to build the lasso.
``` csharp
	public int GetSelected(IEnumerable<ISelectable> selectables,
								  ICollection<ISelectable> result) 
	{
		return 0;
	}
```
Finally, implement the interface to get it to compile.
``` csharp
}
```
</div>

## GUI for the Lasso Selector
### Hooking up the mouse

The Lasso Selector can now hold a list vertices, but we have no way to use it yet. To control the lasso with a mouse, create the following class:

``` csharp
public class UGUILassoSelector : MonoBehaviour, IDragHandler, IEndDragHandler, IBeginDragHandler
{
	LassoSelector lassoSelector;

	void Start()
	{
		lassoSelector = new LassoSelector();
	}

	public void OnBeginDrag(PointerEventData eventData)
	{
		lassoSelector.ExtendLasso(eventData.position);
	}

	public void OnDrag(PointerEventData eventData)
	{
		lassoSelector.ExtendLasso(eventData.position);
	}

	public void OnEndDrag(PointerEventData eventData)
	{
		lassoSelector.Reset();
	}
}
```

As you can see, the class implement a lot of interfaces. These interfaces allow it to get callback from Unity UGUI Event System, in this case, for various drag related events. We can use these events to build the lasso, base on the pointer (mouse/touch) position. These events not only detect drag for us, but also handle both mouse and touch

Create an UGUI Image and attach the script to it:
![](/img/unity-lasso-selection/ugui-lasso-selector-inspector.png)

Set the Image color to transparent if you don't want it to be visible. But the Image component itself is necessary for our script to receive drag events.

### Visualize the lasso
At these point, we can already create the lasso with the mouse. You can `Debug.Log` out the vertices. However we have no feedback as to how it actually look. To draw the lasso, I choose the easiest way of using a Line Renderer.

Back to the UGUILassoSelector class, lets declare and initialize the necessary variables. Make sure to include the `[SerializeField]` attribute so we can assign them in the Unity Inspector. As the Line Renderer should match the cursor on screen, we also need a reference to the camera that we're drawing from.

``` csharp
// UGUILassoSelector.cs
[SerializeField] Camera             rendererCamera;
[SerializeField] LineRenderer       lineRenderer;

void Start()
{
	rendererCamera = rendererCamera ? rendererCamera : Camera.main;
	lineRenderer.positionCount = 0;

	lassoSelector  = new LassoSelector();
}
```

Now, instead of calling `lassoSelector.ExtendLasso()` in the drag events, we should create a private ExtendLasso method, that additionally extend the Line Renderer.
``` csharp
// UGUILassoSelector.cs
void ExtendLasso(Vector2 position)
{
	lassoSelector.ExtendLasso(position);

	if (lineRenderer)
	{
		var posWS = rendererCamera.ScreenToWorldPoint(
			new Vector3(position.x, position.y, rendererCamera.nearClipPlane + 1e-3f)
		);
		lineRenderer.SetPosition(lineRenderer.positionCount++, posWS);
	}
}

public void OnBeginDrag(PointerEventData eventData)
{
	ExtendLasso(eventData.position);
}

public void OnDrag(PointerEventData eventData)
{
	ExtendLasso(eventData.position);
}

public void OnEndDrag(PointerEventData eventData)
{
	lassoSelector.Reset();

	if (lineRenderer)
	{
		lineRenderer.positionCount = 0;
	}
}
```

Create a Line Renderer GameObject from the Unity Editor, tune it to your liking, then assign it to the UGUILassoSelector. Now, we can see how the lasso looked like:

<figure>
{{<gfycat TemptingMarvelousFairybluebird controls>}}
<figcaption><p>Besure to turn on the "loop" checkbox of the line renderer. Otherwise you would get a string, not a lasso</p></figcaption>
</figure>

## Make Colliders Selectable

Next, we need some thing to select. There are many way to implement `ISelectable`. We can get the vertices from the renderer mesh, the renderer bounding box, the colliders, or just the center. I opted to take the data from the colliders, which offers reasonable selections accuracy while not creating too many vertices.

<div class="code-block">

``` csharp
public class SelectableCollider : MonoBehaviour, ISelectable
{
	public IEnumerable<Vector3> Vertices            => vertices;
	public IEnumerable<Vector2> VerticesScreenSpace => verticesScreenSpace;

	public int VerticesSelectedThreshold => vertices.Length / 2;
``` 
We hardcode the amount of selected vertices for the object to be selected to be 50%. You might expose this to the UI to make it configurable.
``` csharp
	Vector3[] vertices            = new Vector3[0];
	Vector2[] verticesScreenSpace = new Vector2[0];
``` 
The vertices are store as Arrays. This is because I do not expect their number or layout to change at runtime.
``` csharp

	public event Action selected;
	public event Action deselected;

	public void OnSelected()
	{
		selected?.Invoke();
	}

	public void OnDeselected()
	{
		deselected?.Invoke();
	}
```
The selected and deselected events are implemented with C# event. But it can easily be implemented with UnityEvent if you want more artist control.
``` csharp
	MeshCollider  meshCollider;
	BoxCollider[] boxColliders;

	public void Init(Func<Vector3, Vector2> worldToScreenPoint)
	{
		meshCollider = GetComponent<MeshCollider>();
		boxColliders = GetComponentsInChildren<BoxCollider>();

		int meshColliderVerticesCount = meshCollider ? 
													meshCollider.sharedMesh.vertexCount : 0;
		int boxColliderVerticesCount  = boxColliders.Length > 0 ? 
													8 * boxColliders.Length : 0;

		int vCount = meshColliderVerticesCount +
                   boxColliderVerticesCount;
		vertices            = new Vector3[vCount];
		verticesScreenSpace = new Vector2[vCount];

		if (meshCollider)
			AddMeshColliderVertices(0);
		if (boxColliders.Length > 0)
			AddBoxColliderVertices(meshColliderVerticesCount);

		InvalidateScreenPosition(worldToScreenPoint);
	}
```
As you can see, the class support a single mesh collider and multiple box colliders. Following the same layout, adding support for additional collider type is trivial.
``` csharp
	void AddMeshColliderVertices(int startOffset)
	{...}
	void AddBoxColliderVertices(int startOffset)
	{...}
```
These 2 methods are straight-forward, so they're excerpted for brevity. You can find them at the repo linked.
``` csharp
	public void InvalidateScreenPosition(Func<Vector3, Vector2> worldToScreenPoint)
	{
		for (var i = 0; i < verticesScreenSpace.Length; i++)
		{
			verticesScreenSpace[i] = worldToScreenPoint(vertices[i]);
		}
	}
```
Lets also implement the `InvalidateScreenPosition` method, defined by the interface. But for real this time.
``` csharp
}
```
</div>

Now you have a script that can be attached to any GameObject with mesh or box colliders, and it would cache a list of screen space postion that can be used for selection. Here how it would look like:

<details>
<summary>Code for visualizing the vertices</summary>

``` csharp
void OnGUI()
{
	foreach (var selectables in selectables)
	{
		foreach (var vertex in selectables.VerticesScreenSpace)
		{
				GUI.Box(new Rect(vertex.x, Screen.height - vertex.y, 1, 1), GUIContent.none);
		}
	}
}
```
</details>

{{<figure src="/img/unity-lasso-selection/screen-pos-from-colliders.png" title="Green boxes are coliders, black are the vertices we generated">}}

Except it doesn't actually do anything. Yet.

The `Init` method haven't been called. Usually, you do initialization in Unity in the Start or Awake method, which will be called by the engine. In there you might use one of the `Find*` methods to find the needed references, the Camera in this case.

So why am I not doing that here? This is an important topic, so I will write a dedicated section for it. Lets talk about ***managers***.

## Side track: Managers, Singleton and dependency management

Manager classes is everywhere in game development. They are used to hold stuffs that are used by many objects (let call them ***users***), such as game settings, or in our case here, a method to convert position from 3D world space to 2D screen-space. Usually we will need many more ***managers***: game manager, players manager, enemies manager, effects manager,...

There are a few problems when using them: 
 - How are the ***users*** going to find them?
   - If we look for the ***managers*** in each type of ***users***, we have to write the same code over and over, with some slight modification, based on each ***users*** need.
   - If each ***managers*** find the ***users*** and give them what they need, ***users*** have to keep track of when they have enough stuffs to work.

 - The managers might need to initialize their state first before they can serve others. How do the ***users*** make sure the ***manager*** is initialized if we go for the first method?
   - Initialize all the ***managers*** in `Awake()`, and the ***users*** in `Start()`?
   - Use Unity Script Execution Order?

 - What if a ***manager*** need others ***managers*** to initialize?

Many tutorial I've seen use the Singleton pattern - basically a static field in each manager class that point to the only instance of that class. 

It solve the first problem - the managers are accessible from anywhere. However, it does not attempt to solve the ordering problems at all. If you ever try to use Singleton for a non trivial project, you will inevitably run into these ordering problems, which often manifest themselve in the form of the non-informative `NullReferenceException`.

Furthermore, using Singleton obscure the ordering of initialization. You might design yourself into some impossible dependency situation without knowing it.

And of course, you can only have a *single* manager of each type. What if you want a SelectablesManager for each players in a multiplayer RTS?

Thankfully. All of the above problems can be solved with a single design pattern: **Dependency Injection**.

Scary name. Even more scary if you Bing it and find frameworks that can look like this:
``` csharp
Container.Bind<ContractType>()
			.WithId(Identifier)
			.To<ResultType>()
			.FromConstructionMethod()
			.AsScope()
			.WithArguments(Arguments)
			.OnInstantiated(InstantiatedCallback)
			.When(Condition)
			.(Copy|Move)Into(All|Direct)SubContainers()
			.NonLazy()
			.IfNotBound();
```

Not to pick on any frameworks - they're there to solve specific problems - but I advises against using any if you don't know what they're solving.

This is what dependency injection will look like for our project:
``` csharp
selectableCollider.Init(worldToScreenPointDelegate);
```

You *inject* the *dependency* by passing it into the `Init` method. That's it. Usually the method would be the constructor, but in Unity you can't really use contructors for MonoBehaviour, so we have to make up something else.

Each ***user***'s Init method will specify what they need, and the ***managers*** will call it whenever they're ready. If an ***user*** need multiple managers, or if a *manager* need other managers, we can make a Manager Manager. I usually just call it Game Manager, which sound less ridiculous.

By ordering these `Init` function calls, we can specify the exact order we want our classes to be initialized. If you find it difficult to order these calls, that a sign you might need some re-architecturing. This is different from if you're using Singleton, which will just result in a bunch of `NullReferenceException`, or worse, wrong value without any error. 

This is the reason I encourage you to never use Singleton except in game jam. The time and brain damage it take to debug dependency issue is never worth the time they save. Using Dependency Injection is easy.

Dependency Injection, when combined with interface, also let you to easily swap out any dependency for another. This is especially useful when you want to do unit test.

Oh, and in case you're wondering, what those complex frameworks do, basically, is to call these Init() methods for you. You'll know when you need them.

## Selectables Manager
With that out of the way, lets implement the only manager we need for this project.

<div class="code-block">

``` csharp
public class SelectablesManager : MonoBehaviour
{
	public Camera selectionCamera;

	public List<ISelectable> Selectables => selectables;

	List<ISelectable>      selectables = new List<ISelectable>();
	Func<Vector3, Vector2> worldToScreenPointDelegate;
```
We cache the `worldToScreenPointDelegate` so we don't have to allocate a new one for every selectables.
``` csharp
	Vector3    lastCameraPosition;
	Quaternion lastCameraRotation;

	void Start()
	{
		var selectableColliders = FindObjectsOfType<SelectableCollider>();
```
<details>
<summary>But Find*() are slow?</summary>
Not really. They usually take an order of magnitude of tens to hundreds of millisecond. Which is a lot if you call them everyframe ( &le; 16.(6)ms), but imperceptible if called once at startup.
</details>

``` csharp
		worldToScreenPointDelegate = 
			worldPos => selectionCamera.WorldToScreenPoint(worldPos);

		foreach (var selectableCollider in selectableColliders)
		{
			selectableCollider.Init(worldToScreenPointDelegate);
```
We `Init` the selectables from here since this is the only dependency they need.
``` csharp
		}

		selectables.AddRange(selectableColliders);

		lastCameraPosition = selectionCamera.transform.position;
		lastCameraRotation = selectionCamera.transform.rotation;
	}

	void LateUpdate()
	{
		var cameraTransform = selectionCamera.transform;
		bool changed = false;

		if (cameraTransform.position != lastCameraPosition)
		{
			changed = true;
			lastCameraPosition = cameraTransform.position;
		}

		if (cameraTransform.rotation != lastCameraRotation)
		{
			changed = true;
			lastCameraRotation = cameraTransform.rotation;
		}

		if (changed)
		{
			foreach (var selectable in selectables)
			{
				selectable.InvalidateScreenPosition(worldToScreenPointDelegate);
			}
		}
	}
```
We check at the end of every frame to see if the camera has moved or rotated, and invalidate all the selectables. If you have a camera controller, you may want to expose an event from there to notify when the camera actually moved, instead of polling like this.
``` csharp
}
```
</div>

## Tying it all together
Now, return to the `UGUILassoSelector` class, lets add reference our new `SelectablesManager`, make sure to add the `[SerializeField]` attribute so we can assign it in the Inspector.
``` csharp
// UGUILassoSelector.cs
[SerializeField] SelectablesManager selectablesManager;
```

Wait a minute! - you said - So what about all the dependency injection things you been ranting about? Aren't we supposed to pass the managers in using an `Init` method?

Glad you asked! See, this is actually another form of dependency injection. Unity Editor is the dependency injector, and by using the `[SerializeField]` attribute, we're declaring what dependencies are needed.

The problem about this method, first, is that we can only inject a few limited Unity types (and our custom subtypes of them). That mean we will have to inject the whole Selectables Manager, even through we only need some members of the object. It make this class, the `UGUILassoSelector`, tightly coupled with the SelectablesManager. We can't really use one without the other. It make unit testing more difficult, and make the class less portable.

Another problem is we need to manually assign the SelectablesManager to every `UGUILassoSelector`, which is only 1. But you can see it wouldn't work in case of the Selectables.

The benefit of this approach is the GUI. Say if you're building a multiplayer RTS, you can give your designer theses scripts, and lets them hook up the Managers to the right players, may be changes the selection color for each player or whatever. Now they're responsible for calling the Init() methods instead of you. Putting the S in SOLID amirite 😁👍.

Now that we have the SelectablesManager along with all of its selectables. We'll give this to the Lasso Selector when we receive the Drag event.

<div class="code-block">

``` csharp
// UGUILassoSelector.cs
List<ISelectable> selected = new List<ISelectable>();
```
We need a place to store the selected objects.
``` csharp
void UnSelectAll()
{
	foreach (var selectable in selected)
	{
		selectable.OnDeselected();
	}

	selected.Clear();
}

public void OnBeginDrag(PointerEventData eventData)
{
	UnSelectAll();
```
Deselect everything when we begin dragging.
``` csharp
	ExtendLasso(eventData.position);
}

public void OnDrag(PointerEventData eventData)
{
	UnSelectAll();
```
Also deselect everything when we are dragging. Because we can create holes in in the lasso. You might want to do some diffing to only invoke the `deselected` event one per drag. Me lazy.
``` csharp
	ExtendLasso(eventData.position);
	lassoSelector.GetSelected(selectablesManager.Selectables, selected);
}
```
</div>

Of course, nothing is selected yet. Our `GetSelected` method is just `return 0`. But now, we're done with all the set up. In the next post, we will get to the meaty part: the lasso selection algorithm.

