+++
title = 'Unity In Depth: Escape from UI Mask'
date = 2020-10-07
draft = false
tags = ["unity", "programming", "graphic"]
+++

This will probably be useful to like 7 people, max; but it was useful to me, so I'm writing about it. In the process, I also explain how the uGUI Masking system work, and why Unity decided not to support soft Mask.

<!--more-->

## Escape what now?

While developing [True Shadows](https://assetstore.unity.com/packages/slug/176322?aid=1011l4nGC), I got into a rather interesting situation with UI Mask. The shadow rendering object have to be a child of the shadow caster object, due to [an Unity bug](https://issuetracker.unity3d.com/issues/prefab-instances-sibling-index-is-not-updated-when-a-lower-index-sibling-is-deleted).

The problem is, the shadow caster can have a mask, which will of course hide the shadow - being its child.

The MaskableGraphic component (Image, RawImage) have this Maskable property that look tempting, but then the shadows will be completely unaffected by any mask. I want the shadow to still be maskable, as if it is a part of the shadow caster. So, it should only ignore the mask of its parent, but not others higher in the hierarchy.

<!--more-->

## Behind the Mask
After years of working Unity, I never give a second thought to how the UI masking system work, despite using it in every single project.

I mean, obviously it is using stencil buffer, but how exactly? How does all the UIs write and read from the stencil buffer but not interfere with each other?

Thankfully, Unity [open-sourced](https://github.com/Unity-Technologies/uGUI) their current UI system (sometime called uGUI).

## Source code adventure

### A guided scary ride
This is the part that we're interest in, simplified. Feel free to just skim through it.
```csharp
Material StencilMaterial.Add(
	Material baseMat,
	int stencilID,
	StencilOp operation,
	CompareFunction compareFunction,
	ColorWriteMask colorWriteMask,
	int readMask,
	int writeMask
);

Material MaskableGraphic.GetModifiedMaterial(Material baseMaterial)
{
	// stencilDepth is the UI depth in masking hierarchy
	int desiredStencilBit = 1 << stencilDepth;

	return StencilMaterial.Add(baseMaterial,
		desiredStencilBit - 1,
		StencilOp.Keep,
		CompareFunction.Equal,
		ColorWriteMask.All,
		desiredStencilBit - 1,
		0
	);
}

Material Mask.GetModifiedMaterial(Material baseMaterial)
{
	// ...

	// stencilDepth is the UI depth in masking hierarchy
	int desiredStencilBit = 1 << stencilDepth;

	var maskMaterial2 = StencilMaterial.Add(
		baseMaterial,
		desiredStencilBit | (desiredStencilBit - 1),
		StencilOp.Replace,
		CompareFunction.Equal,
		m_ShowMaskGraphic ? ColorWriteMask.All : 0,
		desiredStencilBit - 1,
		desiredStencilBit | (desiredStencilBit - 1)
	);
	StencilMaterial.Remove(m_MaskMaterial);
	m_MaskMaterial = maskMaterial2;

	graphic.canvasRenderer.hasPopInstruction = true;
	var unmaskMaterial2 = StencilMaterial.Add(
		baseMaterial,
		desiredStencilBit - 1,
		StencilOp.Replace,
		CompareFunction.Equal,
		0,
		desiredStencilBit - 1,
		desiredStencilBit | (desiredStencilBit - 1)
	);
	StencilMaterial.Remove(m_UnmaskMaterial);
	m_UnmaskMaterial = unmaskMaterial2;
	graphic.canvasRenderer.popMaterialCount = 1;
	graphic.canvasRenderer.SetPopMaterial(m_UnmaskMaterial, 0);

	return m_MaskMaterial;
}
```

If you're unfamiliar with bit fiddling, this might look a bit intimidating. Let break it down.

First, we have `stencilDepth`: if an UI element have 4 masks in their parents, it will have `stencilDepth = 4`. Let plug that in the above calculation:

```csharp
// a binary number with 1 at the fourth position, and 0 everywhere else.
desiredStencilBit = 1 << 4 = b1000
//a binary number with 3 ones on the right
desiredStencilBit - 1 = b1000 - 1 = b0111
//a binary number with 4 ones on the right
desiredStencilBit | (desiredStencilBit - 1) = b1111
```

So to translate the above code:

#### Maskable

```csharp
int desiredStencilBit = 1 << stencilDepth;

return StencilMaterial.Add(baseMaterial,
	desiredStencilBit - 1, // b0111
	StencilOp.Keep,
	CompareFunction.Equal,
	ColorWriteMask.All,
	desiredStencilBit - 1, // b0111
	0
);
```
Translation: An UI element at depth 4 will be `.Keep`, if the last 3 bits of the stencil buffer is `.Equal` to the last 3 bits of `b111`.

In another word, if any of the last 3 stencil bits is not 1, it will be hidden.

#### Mask
```csharp
var maskMaterial2 = StencilMaterial.Add(
	baseMaterial,
	desiredStencilBit | (desiredStencilBit - 1), // b1111
	StencilOp.Replace,
	CompareFunction.Equal,
	m_ShowMaskGraphic ? ColorWriteMask.All : 0,
	desiredStencilBit - 1,
	desiredStencilBit | (desiredStencilBit - 1) // b1111
);
```
Notice the `readmask` of the Mask is the same as the Maskable. Furthermore, all but the rightmost bit of the `stencilId` are also exactly the same. What that mean is a Mask is also Maskable.

Translation: A Mask at depth 4 will `.Replace` the last 4 bits of the stencil buffer with all 1s, only if it is not masked itself.

### The whole point
As you can see, our depth-4 Mask can never hide its fellow depth-4 UIs elements, as it can never write any 0s. It can't show them either: If any of the bits is already 0, then the Mask itself is hidden, and can't write anything to the stencil buffer. For the same reason, it also can't affect any UI element at smaller depth (higher in hierarchy).

Essentially, the whole complicated bit shift thing is a clever way to not allow a Mask to influent its parent or sibling in anyway.

When our depth-4 Mask is not being masked though; it will make sure the 4 rightmost stencil bits are all 1s, so its children - the depth-5 UI elements can show themselves.

Oh, and the stencil buffer is filled with 0s by default, so anywhere the a Mask do not touch, all of its children will not be visible.

### Consequences
This system mean that you can only have 8 level of mask nesting. Which is fine if you ask me.

The bigger problem is masking is 1 bits: a pixel is either masked or not. This is a big pain point for many people.

However, this sacrifice is rewarded with a 3-fold win in performance:
 - You can mask a whole bunch of UIs, using only a single screen-sized 8-bit buffer.
 - Stencil testing is done at the hardware level, so it is essentially free.
 - Stencil testing allow GPU to skip running pixel shader entirely for masked pixels. This is especially important for fill-rate hungry shader.

Imagine writing and reading 8 screen-sized textures in the pixel shader, aahh...



## The Escape

With this fresh knowledge, escaping from the grasp of the parent is obvious: just remove the left-most 1 of the `stencilId`. In fact, it is right there in `Mask.GetModifiedMaterial`. If you're ever looked at `CanvasRenderer` doc and wonder what those `PopMaterial` business was about, this is it. These pop material undo the stencil written by the Masks, so uncles and aunts Mask can't affect their nieces and nephews.

However, you can't just call `GetPopMaterial` and use it, however. These material have ColorWriteMask set to 0, which mean they only write to the stencil buffer. To render something for the human eye, you'll have to build the material with the proper `stencilId` yourself.

This is my current implementation in True Shadow. Material caching and some error checking was omitted for brevity:

```csharp
public Material GetModifiedMaterial(Material baseMaterial)
{
	bool casterIsMask = shadow.GetComponent<Mask>() != null;

	if(!casterIsMask) return baseMaterial;

	mat = new Material(baseMaterial);
	var baseStencilId = mat.GetInt(ShaderId.STENCIL_ID) + 1;

	// Find stencil depth encoded in the material, without having to walk the hierarchy
	int stencilDepth  = 0;
	for (; stencilDepth < 8; stencilDepth++)
	{
		if (((baseStencilId >> stencilDepth) & 1) == 1)
			break;
	}
	stencilDepth = Mathf.Max(0, stencilDepth - 1);

	var stencilId = (1 << stencilDepth) - 1;

	mat.SetInt(ShaderId.STENCIL_ID,        stencilId);
	mat.SetInt(ShaderId.STENCIL_READ_MASK, stencilId);

	return mat;
}
```

### Tip
Whenever you find yourself generating `Material` from script, you must make sure to `Destroy` them. These object, among a few others, are just pointer to native object: they can't be garbage collected by the CLR. I have to thanks a very kind customer of mine, whom reported a memory leak in [Translucent Image](https://leloctai.com/asset/translucentimage/), which led me to this discovery.