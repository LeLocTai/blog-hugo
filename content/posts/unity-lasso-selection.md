+++
title = 'Unity Lasso Selection'
date = 2020-02-08
draft = true
tags = ["Unity", "Programming"]
+++

{{<gfycat SparseFormalElkhound autoplay muted>}}

## Introduction

Between working on my raytracer and wrestling with HDRP for Translucent Image, I

This post is mean to explain the interesting parts of the project, not a step by step tutorial. The full codebase is available at https://github.com/LeLocTai/unity-objects-selections

 <!--more--> 

## Design



## Implement
### Building the lasso
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

afasdf

``` csharp
public void OnBeginDrag(PointerEventData eventData)
{
	UnSelectAll();
	lassoSelector.ExtendLasso(position);
}

void UnSelectAll()
{
	foreach (var selectable in selected)
	{
		selectable.OnDeselected();
	}

	selected.Clear();
}

public void OnDrag(PointerEventData eventData)
{
	UnSelectAll();
	lassoSelector.ExtendLasso(position);
	lassoSelector.GetSelected(selectablesManager.Selectables, selected);
}

public void OnEndDrag(PointerEventData eventData)
{
	lassoSelector.Reset();
}
```

### Visualize the lasso

``` csharp
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

public void OnEndDrag(PointerEventData eventData)
{
	lassoSelector.Reset();

	if (lineRenderer)
	{
		lineRenderer.positionCount = 0;
	}
}
```


### Selectables

``` csharp
public void OnSelected()
{
	selected?.Invoke();
}

public void OnDeselected()
{
	deselected?.Invoke();
}
```

asdsad

``` csharp
MeshCollider  meshCollider;
BoxCollider[] boxColliders;
Vector3[]     vertices            = new Vector3[0];
Vector2[]     verticesScreenSpace = new Vector2[0];
```

asdasd

``` csharp
public void Init(SelectablesManager manager)
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

	for (var i = 0; i < vCount; i++)
	{
		verticesScreenSpace[i] = manager.WorldToScreenPoint(vertices[i]);
	}
}
```

asdasd

``` csharp
void AddMeshColliderVertices(int startOffset)
{
	for (var i = 0; i < meshCollider.sharedMesh.vertices.Length; i++)
	{
		vertices[startOffset + i] = transform.TransformPoint(meshCollider.sharedMesh.vertices[i]);
	}
}
```

asdasd

``` csharp
static readonly Vector3[] BOX_VERTICES_OFFSET = {
	new Vector3(-.5f, -.5f, .5f),
	new Vector3(.5f,  -.5f, .5f),
	new Vector3(-.5f, -.5f, -.5f),
	new Vector3(.5f,  -.5f, -.5f),
	new Vector3(-.5f, .5f,  .5f),
	new Vector3(.5f,  .5f,  .5f),
	new Vector3(-.5f, .5f,  -.5f),
	new Vector3(.5f,  .5f,  -.5f)
};

void AddBoxColliderVertices(int startOffset)
{
	for (var colliderIndex = 0; colliderIndex < boxColliders.Length; colliderIndex++)
	{
		var theBox = boxColliders[colliderIndex];
		for (var vOffsetIndex = 0; vOffsetIndex < BOX_VERTICES_OFFSET.Length; vOffsetIndex++)
		{
			var vOffset = theBox.size;
			vOffset.Scale(BOX_VERTICES_OFFSET[vOffsetIndex]);
			var vertexIndex = startOffset + colliderIndex * BOX_VERTICES_OFFSET.Length + vOffsetIndex;
			vertices[vertexIndex] = theBox.center + vOffset;
			vertices[vertexIndex] = theBox.transform.TransformPoint(vertices[vertexIndex]);
		}
	}
}
```

asdasd

``` csharp
public class SelectablesManager : MonoBehaviour
{
	public Camera selectionCamera;

	public List<ISelectable> Selectables => selectables;

	List<ISelectable> selectables = new List<ISelectable>();


	void Start()
	{
		var selectable = FindObjectsOfType<SelectableCollider>();
		for (var i = 0; i < selectable.Length; i++)
		{
			selectable[i].Init(this);
		}

		selectables.AddRange(selectable);
	}

	public Vector2 WorldToScreenPoint(Vector3 point)
	{
		return selectionCamera.WorldToScreenPoint(point);
	}
}
```



### Finally getting to the 🍖. Lasso selection

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

https://stackoverflow.com/questions/217578/how-can-i-determine-whether-a-2d-point-is-within-a-polygon
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