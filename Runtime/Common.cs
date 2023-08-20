using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace LimWorks.Rendering.URP.ScreenSpaceReflections
{
    public static class Common
    {
        public static int NearestPowerOf2(int number)
        {
            if (number <= 0)
            {
                return 1; // The nearest power of 2 to a non-positive number is 1
            }

            int nearestLowerPower = (int)Math.Pow(2, Math.Floor(Math.Log(number, 2)));
            int nearestHigherPower = (int)Math.Pow(2, Math.Ceiling(Math.Log(number, 2)));

            if (Math.Abs(number - nearestLowerPower) <= Math.Abs(number - nearestHigherPower))
            {
                return nearestLowerPower;
            }
            else
            {
                return nearestHigherPower;
            }
        }
        public static Vector2Int NearestPowerOf2(Vector2Int vector2Int)
        {
            vector2Int.x = NearestPowerOf2(vector2Int.x);
            vector2Int.y = NearestPowerOf2(vector2Int.y);
            return vector2Int;
        }

        public static int NextHighestPowerOf2(int number)
        {
            if (number <= 0)
            {
                return 1; // The next highest power of 2 to a non-positive number is 2^0 = 1
            }

            int exponent = (int)Math.Ceiling(Math.Log(number, 2));
            return (int)Math.Pow(2, exponent);
        }
    }
}
