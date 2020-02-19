+++
title = 'Unity Lasso Selection - Part 2: Point-in-polygon algorithm explained'
date = 2020-02-19
draft = false
tags = ["Unity", "Programming"]
videos = ["https://giant.gfycat.com/SparseFormalElkhound.mp4"]
math = true
+++

## Introduction

In the last post, we talked about how to make thing selectable, and a few ways to connect stuff together. This post will explain the interesting part - the lasso selection algorithm. You can find the complete code here: https://github.com/LeLocTai/unity-objects-selections.

At its core, lasso selection is the problem of testing whether a point in a polygon.

The first thing I thought of when starting this project, is that it would be difficult to do actual point in polygon test - especially for weirdly shaped ones that have crossing edge like those in the gif above. I was going to try to tessellate the polygon into triangles to reduce the problem to point in triangles, which a lot easier.

I discovered that was pretty stupid, after a quick internet search.
 <!--more--> 

## The algorithm

I found this [Wiki page](https://en.wikipedia.org/wiki/Point_in_polygon) and [SO question](https://stackoverflow.com/questions/217578/how-can-i-determine-whether-a-2d-point-is-within-a-polygon), which explained the solution very well. Take a look at this image:

{{<figure src="/img/unity-lasso-selection/recursive-even-polygon.svg" title="By Melchoir - Own work. The algorithm is described at Wise, Stephen (2002). GIS Basics. CRC Press. pp. 66–67. ISBN 0415246512. That source depicts the algorithm in Figure 4.6 on page 67, which is similar in spirit but does not use color or numerical labels., CC BY-SA 3.0, https://commons.wikimedia.org/w/index.php?curid=2974468">}}

If you draw a horizontal ray from left to right, it will start out <span style="color:blue">**outside**</span> of any polygon. This mean all the points on the line also are <span style="color:blue">**outside**</span> of the polygon. If the ray start intersecting the polygon, all the point on the ray to the right of that intersection is now <span style="color:darkred">**inside**</span> the polygon. If it intersect again, now the remaining points are <span style="color:blue">**outside**</span> of the polygon again. So on and so fourth.

To put it in another ways: a point is inside a polygon if the horizontal line crossing that point have an *odd* number of intersections with the polygon on either side of the point.

Finding the intersections of a line and a polygon is finding the intersections of the line with every line that made up the polygon. So our initial problem has been reduced to a line &mdash; line-segment intersection problem. In our case, it even easier as the line is always perfectly horizontal.

## Check if a point in the lasso

Given a `point`, the first step is to loop through the vertices of the lasso in pair. Each pair of vertices would be a line-segment. Remember to include the segment between the last and the first vertices, otherwise our polygon would not be closed.

<div class="code-block">

``` csharp
bool IsPointInLasso(Vector2 point)
{
	int vCount = vertices.Count;
	if (vertices.Count < 2) return point == vertices[0];

	bool inside = false;
	for (int i = 1, j = vCount - 1; i < vCount; j = i++)
	{
		var a = vertices[j];
		var b = vertices[i];

		bool intersectLeft = IsBetween(point.y, a.y, b.y) && 
									IntersectionX(point, a, b) < point.x;
```
For the horizontal line crossing the `point` to intersect with the line-segment `ab`, the point y coordinate must be between the y coordinate of the 2 point `a` and `b`. If it does intersect, we check if the intersection is on the left of the point. On the right also work, as the parity of both side will always be the same.
``` csharp
		inside ^= intersectLeft;
```
The XOR operator `^=` toggle `inside` if `intersectLeft` is true. Since `inside` start as false, after an odd number of toggle, it'll be true. Just some micro optimization.
``` csharp
	}
	return inside;
}

static bool IsBetween(float value, float a, float b)
{
	return a > value != b > value;
}
```
</div>

So how do we find the intersection x coordinate?

Let call the point \\(P\\), and the line segment \\(AB\\), and the intersection \\(X\\):

![](/img/unity-lasso-selection/line-horizon.png)

We want to find X.x, and since:
$$X_x = J_x + JX = B_x + JX \tag 1$$
and we have B.x, what we have to find is JX.

It is clear that the 2 triangle \\(\triangle AKB\\) and \\(\triangle BJX\\) are [similar](https://en.wikipedia.org/wiki/Similarity_(geometry)), so the ratio between the blue lines will be equal to the ratio between orange lines:
$$
\frac {JX}{KB} = \frac {JB}{KA}
\Leftrightarrow
JX = \frac {KB \times JB}{KA} = \frac {(A_x - B_x) \times (P_y - B_y)} {(A_y - B_y)}
$$

Plug that in (1), we can now find X.x:
$$
X_x = B_x + \frac {(A_x - B_x) \times (P_y - B_y)} {(A_y - B_y)}
$$

Or, as code:
``` csharp
static float IntersectionX(Vector2 point, Vector2 a, Vector2 b)
{
	return  b.x + (a.x - b.x) * (point.y - b.y) / (a.y - b.y);
}
```

## Check if a Selectable is selected

The math part is now done, to check if a selectable is selected, we just check if enough of its vertices is selected.

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
The result:
{{<gfycat SparseFormalElkhound controls muted loop>}}
As you can see, the algorithm handle complex shapes just fine.

## Multi-threading

Our algorithm is \\(O(m \times n)\\) where \\(m\\) is the number of vertices in the lasso, and \\(n\\) is the numbers of vertices in all the selectables we have to check. In my test, the FPS drop as the lasso being drawn longer and longer, below 60FPS after just 1 or 2 seconds.

There are optimizations that can be done. For example:
 - Only extend the lasso if the new point is sufficiently far away from the previous point. That would greatly reduce \\(m\\) when the lasso being drawn slowly.
 - Calculate the Selectable vertices from the corners of its bounding box instead of the colliders, or even just the bounding box center point. That would greatly reduce \\(n\\).
 - If most of the selectables are far away from the lasso, you can also first check if the selectable is in the bounding box of the lasso first, which would be must less intensive, and will filter out the majority of them. In other case, like in the test scene above, this will not help.

Those are, however, boring. Threading, on the other hand, is fun! Mostly because our problem is [Embarrassingly parallel](https://en.wikipedia.org/wiki/Embarrassingly_parallel) - each vertices can be check independently.

Usually, threading in Unity is difficult, as all of their classes are not thread safe. Fortunately for us, we are not dealing with Unity here at all! Thanks to our design, the selection system is completely separated from Unity (save for the `Vector` types, which is just a struct): Lasso Selector is not a MonoBehaviour, neither is ISelectable. We are selecting ISelectable, not SelectableCollider.

That said, we do still have some concurrency problem to deal with:
 - Currently, we are adding selected object to the `result` `ICollection` as we find them. However, `ICollection` is not thread safe.
 - ISelectable.OnSelected most likely can't be called from non-main threads, as its subscriber probably interact with Unity
   - Now that I think about it, OnSelected should not be called by GetSelected at all. Well, maybe in part 3.

To deal with these problems, we need a safe place to store our selected temporarily, and copy them over after our threads are all done. There are a few options:
 - A collection with lock
 - 1 collection for each thread
 - One of the `System.Collections.Concurrent`
   - Which one?

I did some quick non-scientific testing and cannot find noticeable different in performance. Maybe more exhaustive testing in part 3? For now, let just use ConcurrentBag, as we don't care about ordering of the selected. 

``` csharp
readonly ConcurrentBag<ISelectable> selectedBag =
													new ConcurrentBag<ISelectable>();
```

<div class="code-block">

``` csharp
public override int GetSelected(IEnumerable<ISelectable> selectables,
										  ICollection<ISelectable> result)
{
	while (selectedBag.TryTake(out _)) { }
```
Clear the bag
``` csharp
	Parallel.ForEach(
		selectables,
```
Spawn up to 1 thread per selectable. `Parallel` will choose the optimal number of threads and schedules work for each thread for us. It also block execution until all threads complete, which is very convenience for us.
``` csharp
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

			if (selectedVerticesCount < 
						selectable.VerticesScreenSpace.Length / 2f)
				return;

			selectedBag.Add(selectable);
```
Instead of adding to the result directly, we need to add the selected to a thread-safe collection (or use lock)
``` csharp
		}
	);

	int selectedCount = 0;
	foreach (var selectable in selectedBag)
	{
		selectable.OnSelected();
		result.Add(selectable);
		selectedCount++;
	}
```
After the threads are all done, we copy all the selected to the result collection. We must also call the selectable's OnSelected event here, as its subscriber is most likely not thread-safe. Better yet, let the caller trigger the event. Probably should not have called it here.
``` csharp

	return selectedCount;
}
```
</div>

## Conclusion

At this point, we have an usable system for lasso selection in Unity. I hope the code and these posts are helpful to you. If you find anything confusing or incorrect, please tell me about it, using whatever platform you found this on, or one of the link in the sidebar/footer.

Again, the full codebase is available at: https://github.com/LeLocTai/unity-objects-selections. Issues and pull-requests are welcomed.