+++
title = 'Unity Lasso Selection tmp'
date = 2020-02-08
draft = true
tags = ["Unity", "Programming"]
videos = ["https://giant.gfycat.com/SparseFormalElkhound.mp4"]
+++

{{<gfycat SparseFormalElkhound autoplay muted loop>}}

## Introduction

<!-- TODO: -->
Note that this post is only mean to explain the interesting parts of the project, not a step by step tutorial. The full codebase is available at https://github.com/LeLocTai/unity-objects-selections.

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
C# events let you subscribe to them and receive notification when they're invoked.
``` csharp
public event Action selected;

selected += () => log("selected"); //subcribe with an anonymous function

selected?.Invoke(); //invoke. the ?. mean only call Invoke() if the event is not null
```

Event can be subcribe to with a delegate, which is a function-as-a-variable. In this case, we uses the premade delegate type `Action`, which is a function that take nothing and return nothing.

## Design

<!-- FIXME: -->
Our system need only 2 interfaces:
 - **Selectable** that can be selected. I defines the as a list of points/vertices. If a certain percentage of these vertices is selected then the whole thing is selected.
 - **Selector**, which when given a list of selectables, produce a subset of them that is selected.
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
public interface Selector
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

### Lasso
The Lasso is essentially a polygon. So the lasso selector should store a (ordered) list of vertices that define that polygon. We can expose these vertices as readonly so later we can have another class that draw the lasso. 

<div class="code-block">

``` csharp
public class LassoSelector : Selector
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
Finally, implement the interface with a stuff
``` csharp
}
```
</div>


## Implement
### GUI for the Lasso Selector
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

As you can see, it implement a lot of interfaces. These interfaces allow it to get callback from Unity UGUI Event System, in this case, for various drag related events. We can use these events to build the lasso, base on the pointer (mouse/touch) position.

Finally, create an UGUI Image and attach the script to it:
![](/img/unity-lasso-selection/ugui-lasso-selector-inspector.png)

Set the image color to transparent if you don't want it to be visible. But the Image component itself is necessary for our script to receive drag events.

### Visualize the lasso
At these point, we can already create the lasso with the mouse. However we have no feedback as to how it actually look. To draw the lasso, I choose the easiest way of using a Line Renderer.

First, declare and initialize the necessary variables. Make sure to include the `[SerializeField]` attribute so we can assign them in the Unity Inspector. As the line render would appear on screen, we also need a reference to the camera that we're drawing from.

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

Create a Line Renderer, tune it to your liking, assign it to the UGUILassoSelector. Now, we can see how the lasso looked like:

{{<gfycat TemptingMarvelousFairybluebird controls>}}


### Selectables

Next step is that we need some thing to select. There are a few way to implement `ISelectable`. We can build the vertices from the renderer mesh, the renderer bounding box, the colliders, or just the center. I opted to take the data from the colliders, which offers a middle ground between selections accuracy and runtime complexity.

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

		int meshColliderVerticesCount = meshCollider ? meshCollider.sharedMesh.vertexCount : 0;
		int boxColliderVerticesCount  = boxColliders.Length > 0 ? 8 * boxColliders.Length : 0;

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
Lets also implement the `InvalidateScreenPosition` method
``` csharp
}
```
</div>

Now you have a script that can be attached to any GameObject with mesh or box colliders, and it would cache a list of screen space postion that can be used for selection. Here how it would look like:

![](/img/unity-lasso-selection/screen-pos-from-colliders.png)

Except it doesn't actually do anything. Yet.

Aside from the fact that I didn't show the code for visualizing the vertices, which is reasonably trivial, the init method isn't getting called. Usually, you do initialization in Unity in the Start or Awake method, with one of the `Find*` methods to find needed references.

So why am I not doing that here? Lets talk about ***managers***.

### Side track: managers, singleton and dependency management
Manager classes is almost always used in game development. They are used to hold stuffs that are used by many objects (let call them ***users***), such as game settings, or in our case here, a method to convert position from 3D world space to 2D screen-space. Usually we will need many more ***managers***: game manager, players manager, enemies manager, effects manager,...

There are a few problems when using them: 
 - How are the ***users*** going to find them?
   - If we look for the ***managers*** in each type of ***users***, we have to write the same code over and over, with some slight modification, based on each ***users*** need.
   - If each ***managers*** find the ***users*** and give them what they need, ***users*** have to keep track of when they have enough stuffs to work.

 - The managers might need to initialize their state first before they can serve others. How do the ***users*** make sure the ***manager*** is initialized if we go for the first method?
   - Initialize all the ***managers*** in `Awake()`, and the ***users*** in `Start()`?
   - Use Unity Script Execution Order features?

 - What if a ***manager*** need others ***managers*** to initialize?

Many tutorial I've seen use the Singleton pattern - basically a static field in each manager class that point to the only instance of that class. 

It solve the first problem - the managers are accessible from anywhere. However, it does not attempt to solve the ordering problems at all. If you ever try to use Singleton for a non trivial project, you will inevitably run into these ordering problems, which often manifest themselve in the form of the non-informative `NullReferenceException`.

Furthermore, using Singleton obscure the ordering of initialization. You might design yourself into some impossible dependency situation without knowing it.

And of course, you can only have a *single* manager of each type. What if you want a SelectablesManager for each players in a multiplayer RTS?

Thankfully. All of the above problems can be solved with a single design pattern: **Dependency Injection**.

Scary name. Even more scary if you Bing™ it and find frameworks that can look like this:
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

This is what dependency injection look like for our project:
``` csharp
selectableCollider.Init(worldToScreenPointDelegate);
```

You *inject* the *dependency* by passing it into the `Init` method. That's it. Usually the method would be the constructor, but in Unity you can't really use contructors for MonoBehaviour, so we have to make up something else.

Each ***user***'s Init method will specify what they need, and the ***managers*** will call it whenever they're ready.

If an ***user*** need multiple managers, or if a *manager* need other managers, we can make a Manager Manager. I usually just call it Game Manager, which sound less ridiculous.

By ordering these `Init` functions, we can specify the exact order we want our classes to be initialized. If you find it difficult to order these functions, that a clear sign that you have circular dependency, and need some re-architecturing. This is different from if you're using Singleton, which will just result in a bunch of `NullReferenceException`.

Oh, and in case you're wondering, what those complex frameworks do basically is to call these Init() methods for you. You'll know when you need them.

### Selectables Manager
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
We cache the `worldToScreenPointDelegate` so we don't allocate a new one for every selectables.
``` csharp
	Vector3    lastCameraPosition;
	Quaternion lastCameraRotation;

	void Start()
	{
		var selectableColliders = FindObjectsOfType<SelectableCollider>();

		worldToScreenPointDelegate = 
			worldPos => selectionCamera.WorldToScreenPoint(worldPos);

		foreach (var selectableCollider in selectableColliders)
		{
			selectableCollider.Init(worldToScreenPointDelegate);
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
We check at the end of every frame to see if the camera has moved or rotated in that frame, and invalidate all the selectables. If you have a camera controller, you may want to expose an event from there to notify when the camera actually moved, instead of polling like this.
``` csharp
}
```
</div>

### Finally getting to the 🍖. Lasso selection

At its core, lasso selection is the problem of testing whether a point in a polygon.

First thing I thought of when starting this project, is that it will be difficult to do actual point in polygon test - especially for weirdly shaped ones that have crossing edge like those in the 2 gifs above. I almost tried to tessellate the polygon to triangles to reduce the problem to point in triagles, which is easy.

I was completely wrong.

A quick internet search lead me to this [Wiki page](https://en.wikipedia.org/wiki/Point_in_polygon) and [SO question](https://stackoverflow.com/questions/217578/how-can-i-determine-whether-a-2d-point-is-within-a-polygon), which explained the solution very well. Look at this image:

{{<figure src="/img/unity-lasso-selection/recursive-even-polygon.svg" title="By Melchoir - Own work. The algorithm is described at Wise, Stephen (2002). GIS Basics. CRC Press. pp. 66–67. ISBN 0415246512. That source depicts the algorithm in Figure 4.6 on page 67, which is similar in spirit but does not use color or numerical labels., CC BY-SA 3.0, https://commons.wikimedia.org/w/index.php?curid=2974468">}}

If you draw a horizontal ray from left to right, it will start out outside of the polygon. This mean all the point on the line also are outside of the polygon.

If the ray start intersecting the polygon, all the point on the ray to the right of that intersection is now inside the polygon. If it intersect another time, then now the remaining points are outside of the polygon again. So on and so fourth.

To put it in another ways: a point is in a polygon if the horizontal line crossing that point have an *odd* number of intersections with the polygon on either side of the point.

To find the intersections of a line and a polygon is essentially finding the intersection of the line with every line that made up the polygon. Line - line-segment intersection, which is very easy. In our case, it even easier as the line is always perfectly horizontal.

Unfortunately, all of the sites I found did not explain the simplified line-segment, horizon intersection math, so I will attempt to do so here.


``` csharp
bool IsPointInLasso(Vector2 point)
{
	int vCount = vertices.Count;
	if (vCount < 2) return point == vertices[0];

	bool inside = false;
	for (int i = 1, j = vCount - 1; i < vCount; j = i++)
	{
		var a = vertices[j];
		var b = vertices[i];

		inside ^= IsBetween(point.y, a.y, b.y) &&
                point.x < (a.x - b.x) * (point.y - b.y) / (a.y - b.y) + b.x;
	}

	return inside;
}

static bool IsBetween(float value, float a, float b)
{
	bool aAbovePoint = a > value;
	bool bAbovePoint = b > value;
	return aAbovePoint != bAbovePoint;
}
```

``` csharp
public override int GetSelected(IEnumerable<ISelectable> selectables, ref List<ISelectable> result)
{
	int selectedCount = 0;
	foreach (var selectable in selectables)
	{
		int selectedVerticesCount = 0;
		foreach (var vertex in selectable.VerticesScreenSpace)
		{
			if (IsPointInLasso(vertex))
			{
				selectedVerticesCount++;
			}
		}

		if (selectedVerticesCount < selectable.VerticesScreenSpace.Length / 2f) continue;

		selectable.OnSelected();
		result.Add(selectable);
		selectedCount++;
	}

	return selectedCount;
}
```

### Multi-threading

``` csharp
readonly ConcurrentBag<ISelectable> selectedBag = new ConcurrentBag<ISelectable>();

public override int GetSelected(IEnumerable<ISelectable> selectables, ICollection<ISelectable> result)
{
	while (selectedBag.TryTake(out _)) { }

	Parallel.ForEach(
		selectables,
		selectable =>
		{
			int selectedVerticesCount = 0;
			for (var i = 0; i < selectable.VerticesScreenSpace.Length; i++)
			{
				var vertex = selectable.VerticesScreenSpace[i];
				if (IsPointInLasso(vertex))
				{
					selectedVerticesCount++;
				}
			}

			if (selectedVerticesCount < selectable.VerticesScreenSpace.Length / 2f) return;

			selectedBag.Add(selectable);
		}
	);

	int selectedCount = 0;
	foreach (var selectable in selectedBag)
	{
		selectable.OnSelected();
		result.Add(selectable);
		selectedCount++;
	}

	return selectedCount;
}
```