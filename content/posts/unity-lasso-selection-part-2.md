+++
title = 'Unity Lasso Selection - Part 2: Point-in-polygon algoritm explained'
date = 2020-02-15
draft = true
tags = ["Unity", "Programming"]
videos = ["https://giant.gfycat.com/SparseFormalElkhound.mp4"]
+++

{{<gfycat SparseFormalElkhound controls muted loop>}}

## Introduction

This post build upon the last post, but relatively independence if you only care about the algorithm. If you going to use this in Unity, and consider yourself beyond beginner, but struggle with more complex projects without tutorials, the last post might be of interest.

At its core, lasso selection is the problem of testing whether a point in a polygon.

The first thing I thought of when starting this project, is that it would be difficult to do actual point in polygon test - especially for weirdly shaped ones that have crossing edge like those in the gif above. I was going to try to tessellate the polygon into triangles to reduce the problem to point in triagles, which a lot easier.

I was completely wrong.
 <!--more--> 

## The algorithm


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

## Multi-threading

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