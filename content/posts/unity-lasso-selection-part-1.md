---
date: "2020-02-18T00:00:00+07:00"
draft: true
tags:
- Unity
- Programming
title: 'Unity Lasso Selection - Part 1: Making thing Selectable'
videos:
- https://giant.gfycat.com/SparseFormalElkhound.mp4
---

{{<gfycat SparseFormalElkhound controls requestautoplay muted loop>}}

## The boring part

This first post go through the process of designing and building all the infrastructure needed for a selection system in Unity Engine, including some tips for managing dependency between Unity scripts.

While this seem mundane, a good design is extremely important for any project:
 - They lets you extend them easily, without tearing thing apart.
 - It's easy to unit test, so you're confident that your new feature doesn't break any things.
 - It's portable, so you can pull it from one project and plug it into another, without having to carry over a bunch of duct tape.

If these points is seem unclear to you, they will once you have to deal with a sufficient amount of old code. Skip this post for now.

If you're only interested in the lasso selection algorithm, it'll be in the next part. If you just want something you can use, the Github link is below.

Note that this series is only mean to cover the interesting parts of the project, not a step by step tutorial. If you just use the code here, it probably will not run. As such, these posts are not suited for complete beginner. 

The full codebase is available at https://github.com/LeLocTai/unity-objects-selections.

 <!--more--> 

## The interfaces

Our system need 2 interfaces:
 - **Selectable** that can be selected. I defines the as a list of points/vertices. If a certain percentage of these vertices is selected then the whole thing is selected.
 - **Selector**, which when given a list of selectables, produce a subset of them that is selected.

Using interfaces make it easy to swap out implementation without changing the users. So if we want to create a rectangle selection method, or if we want to make selectables from 2D Sprite, we don't have to touch anything unrelated - just implement the right interface.

### Selectable

<div class="code-block">

``` csharp
public interface ISelectable
{
	IEnumerable<Vector3> Vertices            { get; }
	IEnumerable<Vector2> VerticesScreenSpace { get; }
```
Since most form of selection are done in screen space, we should cache the screen-space position of the vertices to avoid having to do the conversion every time, as that would requires a relatively expensive matrix multiplication.
``` csharp
	int VerticesSelectedThreshold { get; }
```
We want to be able to select an object, even if our lasso does not fully cover it. So we need to provide a number of vertices for the shape to be consider selected. This is a terrible name btw, suggestions are welcome.
``` csharp
	void InvalidateScreenPosition(Func<Vector3, Vector2> worldToScreenPoint);
```
We expect the camera to changes, so we need a way to notify the selectable to update it screen-space position.
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

Instead of returning a collection, we return the amount of item selected, and add to the provided ICollection instead.

This is to avoid allocating a new collection object every time we need selecting, which is usually every 16.(6)ms. The garbage collector will cause lag spike when it run, so we generate as little garbage as possible.

<details>
<summary>Speaking of allocation...</summary>

Using `IEnumerable` for the selectables have an unfortunate consequence: the runtime will always allocate an `IEnumerator` object on the heap when we want to loop through the parameter.

Normally, generic collections such as List implement `IEnumerable.GetEnumerator()` with a struct, which will allocate on the stack and not be handled by the garbage collector.

In this case, I choose to trade the slight sustained performance gain for more flexible code.

</details>

## Lasso Selector

A Lasso is essentially a polygon. So the lasso selector should store a list of vertices that define it. We can expose these vertices as readonly so later we can have another class that draw the lasso. 

<div class="code-block">

``` csharp
public class LassoSelector : ISelector
{
	readonly List<Vector2> vertices = new List<Vector2>();
	public List<Vector2> Vertices => vertices;
```

``` csharp
	public void ExtendLasso(Vector2 newPoint)
	{
		Vertices.Add(newPoint);
	}

	public void Reset()
	{
		Vertices.Clear();
	}
	...
}
```
</div>

<details>
<summary>readonly but not really</summary>

Both the `readonly` keyword and the lack of setter on the property do not prevent other from modify the `vertices` List, as the variable is just a reference.

The proper way to implement readonly List is to make the property private, and create a public method that expose a way to access the List. Me lazy.

</details>

Notice that the LassoSelector is just a plain C# class - not a MonoBehaviour. It handle the selection logic, but not how it can be created or displayed. This way, you can have any front-end for it. 

## GUI for the Lasso Selector

Let build that front-end, using UGUI.

### Hooking up the mouse

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

The interfaces that we're inheriting from are part of UGUI's Event System. They handle both mouse and touch. They're also only triggered when we drag on the RectTransform that the script attached to:

![](/img/unity-lasso-selection/ugui-lasso-selector-inspector.png)

Set the Image color to transparent if you don't want it to be visible. But the Image component itself is necessary for our script to receive drag events.

### Visualize the lasso
We can now draw the lasso with the mouse. You can `Debug.Log` out the vertices. However we have no feedback as to how it actually look. The easiest way to draw the lasso would be a Line Renderer.

Back to `UGUILassoSelector`. As the Line Renderer should match the cursor on screen, we also need a reference to the camera that is rendering the screen.

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
<figcaption><p>Be sure to turn on the "loop" checkbox of the line renderer. Otherwise you would get a rope, not a lasso</p></figcaption>
</figure>

## Make things Selectable

Next, we need some thing to select. You can make anything `ISelectable`, as long as you somehow define it as a list of points. Example are: Renderer mesh, Renderer bounding box, Colliders, or just the center. 

I opted to use the colliders, which offers reasonable selections accuracy while not creating too many vertices.

<div class="code-block">

``` csharp
public class SelectableCollider : MonoBehaviour, ISelectable
{
	public IEnumerable<Vector3> Vertices            => vertices;
	public IEnumerable<Vector2> VerticesScreenSpace => verticesScreenSpace;

	public int VerticesSelectedThreshold => vertices.Length / 2;
``` 
I hard-coded the amount of selected vertices for the object to be selected to be 50%. You might want to expose this to the UI to make it configurable.
``` csharp
	Vector3[] vertices            = new Vector3[0];
	Vector2[] verticesScreenSpace = new Vector2[0];
``` 
The vertices are store in Arrays. This is because I do not expect the amount or layout of the vertices to change at runtime.
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
calculate the new screen-position when requested.
``` csharp
}
```
</div>

Now you have a script that can be attached to any GameObject with mesh or box colliders, and it would cache a list of screen space position that can be used for selection. Here how it would look like:

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

{{<figure src="/img/unity-lasso-selection/screen-pos-from-colliders.png" title="Green boxes are colliders, black are the vertices we generated">}}

Except it doesn't actually do anything. Yet.

The `Init` method haven't been called. Usually, in Unity, you do initialization in the Start or Awake method, which will be called by the engine. In there you might use one of the `Find*` methods to find the needed references, the Camera in this case.

We will not be finding the Camera here. Instead, we will be using dependency injection to acquire only the method we need.

<details>
<summary>Rant: Managers, Singleton and dependency management</summary>
Manager classes is everywhere in game development. They are used to hold stuffs that are used by many objects (let call them *users*), such as game settings, or in our case here, a method to convert position from 3D world space to 2D screen-space. Usually we will need many more *managers*: game manager, players manager, enemies manager, effects manager,...

There are a few problems when using these managers: 
 - How are the *users* going to find them?
   - If we look for the *managers* in each *users*, we have to write the same code over and over, with some slight modification, based on each *users* need.
   - If each *managers* find the *users* and set their fields, *users* have to keep track of when they have enough stuffs to work.
   - Singleton?

 - Some *managers* might need to initialize their state first before they can serve others. How do the *users* make sure the *manager* is initialized when they want to use them?
   - Have an `isReady` field and poll???
   - Initialize all the *managers* in `Awake()`, and the *users* in `Start()`?
   - Use Unity Script Execution Order?

 - What if a *manager* need others *managers* to initialize?
   - Awake/Start would not be sufficient.
   - Using Script Execution Order is messy. Logic is spread everywhere, order is not apparent just looking at the code. Difficult to transfer to other projects.

Many tutorial I've seen use the Singleton pattern - basically a static field in each manager class that point to the only instance of that class. 

It solve the first problem - the managers are accessible from anywhere. However, it does not attempt to solve the ordering problems at all. If you ever try to use Singleton for a non trivial project, you will inevitably run into these ordering problems, which often manifest themselves in the form of the non-informative `NullReferenceException`.

Furthermore, using Singleton obscure the ordering of initialization. You might create circular dependency, with no clear indication of the situation.

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

This is what dependency injection will look like for our project:
``` csharp
selectableCollider.Init(worldToScreenPoint);
```

You *inject* the *dependency* by passing it into a method. That's it. Usually the method would be the constructor, but in Unity you can't really use constructors for MonoBehaviour, so we have to make up something else.

Each *user*'s `Init` method will specify what they need in their argument list, and the *managers* will call it with the appropriated dependencies, whenever they're ready. 

If an user need multiple managers, or if a manager need other managers, we can make a Manager Manager. I usually just call it Game Manager, which sound less ridiculous.

By ordering these `Init` function calls, we can specify the exact order we want our classes to be initialized. If you find it difficult to order these calls, that a sign you might need some re-architecture. This is different from if you're using Singleton, which will just result in a bunch of `NullReferenceException`, or worse, wrong value without any error. 

This is the reason I encourage you to never use Singleton (may be except in game jam). The time and brain damage it take to debug missing/incorrect dependency issues is never worth the saved by Singleton. Using Dependency Injection can be very easy.

Dependency Injection, when combined with interface, also let you to easily swap out any dependency for another. This is especially useful when you want to do unit test.

Oh, and in case you're wondering, what those complex looking frameworks do; they basically call these Init() methods for you. If you ever need them, you'll know.
</details>

## Selectables Manager

We need something to help us find all the `ISelectables` to feed the `LassoSelector`.

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
	void Start()
	{
		var selectableColliders = FindObjectsOfType<SelectableCollider>();
```
<details>
<summary>Isn't Find*() slow?</summary>
Not really. They can take an order of magnitude of tens to hundreds of millisecond. Which is a lot if you call them every frame ( &le; 16.(6)ms), but imperceptible if called once at startup.
</details>

``` csharp
		worldToScreenPointDelegate = 
			worldPos => selectionCamera.WorldToScreenPoint(worldPos);

		foreach (var selectableCollider in selectableColliders)
		{
			selectableCollider.Init(worldToScreenPointDelegate);
```
This line is all the Dependency Injection. 25-dollar term for a 5-cent concept.
``` csharp
		}

		selectables.AddRange(selectableColliders);
	}

	void LateUpdate()
	{
		bool cameraChanged;

		...

		if (cameraChanged)
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

Back to `UGUILassoSelector`, lets add a reference to our new `SelectablesManager`, make sure to add the `[SerializeField]` attribute so we can assign it in the Inspector.
``` csharp
// UGUILassoSelector.cs
[SerializeField] SelectablesManager selectablesManager;
```

Wait a minute! - you said - So what about all the dependency injection things you been rambling about? Aren't we supposed to pass in the managers using an `Init` method?

Glad you asked! See, this is actually dependency injection. Unity Editor is the dependency injector, and by using the `[SerializeField]` attribute, we're declaring what dependencies are needed. You've been using DI all this time!

There are a few problems with this method:
 - Can only inject a few limited Unity types: we have to inject the whole Selectables Manager, even through we only need some members of the object. It make `UGUILassoSelector` tightly coupled with `SelectablesManager`. We can't use one without the other.
 - No control of the exact ordering - you have to manage with a few methods like Start and Awake. In this case, the `UGUILassoSelector` don't need the `SelectablesManager` stuffs until the user try to drag something, which will always be after the Start method is completed.
 - Need to manually assign the SelectablesManager to every `UGUILassoSelector`, which is only 1 in this case, but you can see it wouldn't work in case of the SelectableColliders.

The most notable benefit of this approach is the GUI. Say if you're building a multiplayer RTS, you can give your designer theses scripts, and lets them hook up the Managers to the right players, may be changes the selection color for each player or whatever. Now they're responsible for calling the Init() methods instead of you. Putting the S in SOLID amirite 😁👍.

Now that we have a way to retrieve all the selectables. We can give this to the Lasso Selector when we receive the Drag event.

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
	ExtendLasso(eventData.position);
}

public void OnDrag(PointerEventData eventData)
{
	UnSelectAll();
```
Deselect everything when we are dragging, as we can create holes in in the lasso. You might want to do some diffing to only invoke the `deselected` event one per drag. Me lazy.
``` csharp
	ExtendLasso(eventData.position);
	lassoSelector.GetSelected(selectablesManager.Selectables, selected);
}
```
</div>

We're done with all the set up. In the next post, we will get to the meaty part: the lasso selection algorithm.
