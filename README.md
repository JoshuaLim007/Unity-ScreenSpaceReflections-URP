# Unity-ScreenSpaceReflections-URP

SSR solution for Unity URP. Supports Linear Tracing and Hi Z tracing. The package includes SSR render feature and Hierarchical Min-Z Depth Buffer render feature. 
**Created by Joshua Lim**

## **9/10/23 4.2.0 - 4.1.0 changelog**
New Features
 - Improved glossy reflections
 - Added downsampling settings for hi-z trace mode

## **Support this project**

[Donation link Here](https://www.paypal.com/donate/?business=757SZWEAT9TBU&no_recurring=1&item_name=Feel%20free%20to%20donate%20anything%20or%20nothing.&currency_code=USD)

## **Images**

![enter image description here](https://i.imgur.com/HmTwsHf.png)
![enter image description here](https://i.imgur.com/IRp0sLc.png)
![enter image description here](https://i.imgur.com/cU5WEE7.png)

# **Installation Instructions:**

**Instructions**:
1. Copy: "https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP.git"
2. Go into the package manager in unity
3. Select "add package from git url"
4. Paste the link into the text entry
5. Press "add"

**Requirements**:
- Unity URP 12 or newer
- Unity 2021 LTS or newer  

In your URP Asset
![SSR ScreenShot 1](https://i.imgur.com/3qgwonV.png  "Instructions")

**Tracing Modes**

- Linear Tracing

- Hi-Z Tracing

![enter image description here](https://i.imgur.com/8ewV9b7.png)
Hi Z tracing requires "Depth Pyramid" render feature to be added in the pipeline asset. The Depth Pyramid is included in this package.

# **API:**
![enter image description here](https://i.imgur.com/0hVpaD2.png)

## **Changing settings during runtime**

### void LimSSR.SetSettings(ScreenSpaceReflectionsSettings o)


-  `o.StepStrideLength` = The length of each ray march stride. Increasing this will reduce image quality but allow for further objects to be visible in the reflections.

-  `o.MaxSteps` = The number of steps the shader does before ending the ray march. Increasing this will allow further objects to be visible in the reflections but reduce performance.

-  `o.Downsample` = The number of times the working resolution is downscaled. Increasing this will reduce image quality but increase performance.

-  `o.MinSmoothness` = The minimum smoothness of a material has to be in order to have reflections.

> For the best quality, try to minimize `StepStrideLength` and maximize `MaxSteps`


### bool LimSSR.Enabled

-  `True`: Enables effect
-  `False`: Disables effect

> Enables or disables the SSR shader

static RaytraceModes TracingMode

> Sets the tracing mode: Linear tracing, or Hi Z tracing

# Known Limitations and bugs
- Wider apart the near and far clip plane, more banding artifact appears.
- Far reflections are inaccurate and have banding artifact.
- Transparent objects cannot have reflections.
- Transparent objects are not correctly reflected onto objects.
- Downsampling ssr on hi-trace mode causes it to break.
- Current fix for non-power of 2 resolutions causes warping around edges of objects with a reflection behind it.
- Hi-z trace cannot have camera facing reflections.
- No support for VR and Mobile devices 


# Resources and References
[Screen Space Reflection | 3D Game Shaders For Beginners (lettier.github.io)](https://lettier.github.io/3d-game-shaders-for-beginners/screen-space-reflection.html)

[Screen Space Reflections : Implementation and optimization – Part 1 : Linear Tracing Method – Sugu Lee (wordpress.com)](https://sugulee.wordpress.com/2021/01/16/performance-optimizations-for-screen-space-reflections-technique-part-1-linear-tracing-method/)

[Screen Space Reflections : Implementation and optimization – Part 2 : HI-Z Tracing Method – Sugu Lee (wordpress.com)](https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method/)

[bitsquid: development blog: Notes On Screen Space HIZ Tracing](http://bitsquid.blogspot.com/2017/08/notes-on-screen-space-hiz-tracing.html)

[Screen Space Reflections in Killing Floor 2 (sakibsaikia.github.io)](https://sakibsaikia.github.io/graphics/2016/12/26/Screen-Space-Reflection-in-Killing-Floor-2.html)

[Hierarchical Depth Buffers - Mike Turitzin](https://miketuritzin.com/post/hierarchical-depth-buffers/#:~:text=Overview,the%20full%2Dresolution%20buffer%27s%20dimensions.)
