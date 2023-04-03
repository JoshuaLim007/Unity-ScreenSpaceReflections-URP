
# Unity-ScreenSpaceReflections-URP
SSR solution for Unity URP. Supports Linear Tracing and Hi Z tracing. The package includes SSR render feature and Hierarchical Min-Z Depth Buffer render feature.

**Donation to help me out**
[Click Here](https://www.paypal.com/donate/?business=757SZWEAT9TBU&no_recurring=1&item_name=Feel%20free%20to%20donate%20anything%20or%20nothing.&currency_code=USD)

**Images**
![enter image description here](https://i.imgur.com/HmTwsHf.png)
![enter image description here](https://i.imgur.com/IRp0sLc.png)
![enter image description here](https://i.imgur.com/cU5WEE7.png)
**Requirements**:

- Unity URP 12 or newer

- Unity 2021 LTS or newer

Does not support VR.
  **Installation Instructions:**
1. Copy: "https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP.git"
2. Go into the package manager in unity
3. Select "add package from git url"
4. Paste the link into the text entry
5. Press "add"

In your URP Asset
![SSR ScreenShot 1](https://i.imgur.com/3qgwonV.png  "Instructions")

**Tracing Modes**
 - Linear Tracing
 - Hi-Z Tracing
 
![enter image description here](https://i.imgur.com/8ewV9b7.png)
Hi Z tracing requires "Depth Pyramid" render feature to be added in the pipeline asset. The Depth Pyramid is included in this package.

**API:**
![enter image description here](https://i.imgur.com/0hVpaD2.png)

**Changing settings during runtime**

    void LimSSR.SetSettings(ScreenSpaceReflectionsSettings o)

-  `o.StepStrideLength` = The length of each ray march stride. Increasing this will reduce image quality but allow for further objects to be visible in the reflections.
-  `o.MaxSteps` = The number of steps the shader does before ending the ray march. Increasing this will allow further objects to be visible in the reflections but reduce performance.
-  `o.Downsample` = The number of times the working resolution is downscaled. Increasing this will reduce image quality but increase performance.
-  `o.MinSmoothness` = The minimum smoothness of a material has to be in order to have reflections.
> For the best quality, try to minimize `StepStrideLength` and maximize `MaxSteps`

    bool LimSSR.Enabled

- `True`: Enables effect
- `False`: Disables effect
> Enables or disables the SSR shader

    static RaytraceModes TracingMode

> Sets the tracing mode: Linear tracing, or Hi Z tracing
