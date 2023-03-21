# Unity-ScreenSpaceReflections-URP
SSR solution for Unity URP 

![SSR ScreenShot](https://i.imgur.com/Um2zfmO.jpg "SSR Sample Scene")

Requirements:
Unity URP 12
Unity 2021 LTS

Will not work with any other Unity Versions. I will only supporting Unity 2021 LTS.

Installation Instructions:
1. Copy: "https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP.git"
2. Go into the package manager in unity
3. Select "add package from git url"
4. Paste the link into the text entry
5. Press "add"

Using it:

In your URP Asset
![SSR ScreenShot 1](https://i.imgur.com/3qgwonV.png "Instructions")

API:
![SSR ScreenShot 2](https://i.imgur.com/3KhAHiX.png "Instructions")

**Changing settings during runtime**

    void LimSSR.SetSettings(ScreenSpaceReflectionsSettings o)

 - `o.StepStrideLength` = The length of each ray march stride. Increasing this will reduce image quality but allow for further objects to be visible in the reflections.
   
 - `o.MaxSteps` = The number of steps the shader does before ending the ray march. Increasing this will allow further objects to be visible in the reflections but reduce performance.

   

 - `o.Downsample` = The number of times the working resolution is   downscaled by 2x. Increasing this will reduce image quality but   increase performance.

   

 - `o.MinSmoothness` = The minimum smoothness of a material has to be in order to have reflections.

> For the best quality, try to minimize `StepStrideLength` and maximize `MaxSteps`

    bool LimSSR.Enabled
    
 - True: Enables effect
 - False: Disables effect

