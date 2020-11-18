---
date: "2020-10-05T00:00:00+07:00"
draft: true
tags:
- unity
- programming
title: How to create soft shadow for Unity ui
---

Unity only provide hard UI shadow pro out-of-the-box. We can manually create soft shadow in an image editor and place it into our hierarchy with an Image, but this is very tedious. Wouldn't it be nice if this automatically done within Unity? Even better, can we generate soft shadows at runtime, so no baking is required, and so we can animate them however we like?

<!--more-->

## Shadow Generation

There are 2 approach to creating UI soft shadow: SDF based and blur filter based. Each with their advantage and disadvantage.

### SDF

Signed Distance Field/Function is widely loved among graphic programmer for their versatility. They can help accelerate ray-tracing to render complex shapes, or provide fast realtime soft shadow or global illumination.

Most Unity user probably already use SDF through TextMesh Pro, which also support soft shadow. If you're familiar with TextMesh Pro, you can probably guess the short coming of SDF-based soft shadow this point.

Despite being relatively fast, SDF-based method can't generate *true* 2D soft shadow, only an approximation. It is fine for small shadows, but as you crank up the shadow size, ugly artifacts will show up, most noticeable at sharp corner.

Here's an example from Stephan himself. Notice how sharp concave corners have lighter penumbra, convex corners darker. The penumbra should be uniform around the perimeter of the shape. This artifact get a lot more noticeable as the shadow get bigger.

{{< figure src="https://lh3.googleusercontent.com/-bzAuZkDtPT0/UvXkDXhAOLI/AAAAAAAABok/dEOG7u9eZ10/w1443-h825-no/TextMesh+Pro+-+Font+Styling+%2526+Texturing+Progression+2+%2528Close+up%2529.PNG" title="TextMesh Pro Shadow. From: https://forum.unity.com/threads/textmesh-pro-advanced-text-rendering-for-unity-beta-now-available-in-asset-store.227790/" >}}

### Blur Filter

The only way to generate high quality UI soft shadows is using a Gaussian blur filter. In fact, this is how it is done in Chrome (I checked, but can't find the exact file to link to now, the project is like 7GB). To be more accurate, this is how its done in Skia, which is used by Chromium, and also Flutter.

However, Gaussian blur is known to be very slow. There are many the well known optimization to help speed it up, but ultimately, if you're targeting constrained platforms like mobile, the speed of your algorithm will limit the size of your shadows, or how you can animate them.

If you only use rectangle or rounded rectangle for your UI, there a pretty recent [method](https://raphlinus.github.io/graphics/2020/04/21/blurred-rounded-rects.html) to speed up blurring these shapes even more. Interestingly, this method also rely on SDF, but does not cause the sharp transition artifact, by exploiting the continuous curvature perimeter of the squircle.

Unlike every mobile/web app these day, however, games are much more expressive when in come to UI, so this method will not fit most games. Often time though, designer have to fit their product to the technology, unfortunately.


### *The* Choice

Ultimately, it up to you to decide the best method for your game. If you only use simple shape, SDF based method is probably the best.

If you looking for a more flexible method, or if you want your shadows to inherit the color of the caster, you will need Gaussian blur based method.

{{< figure src="/img/ui-shadow/google-play-games-colored-shadow.png" title="Colored soft shadow that take on the color of the shadow caster. Google Play Games: https://play.google.com/store/apps/details?id=com.google.android.play.games&hl=en" >}}

