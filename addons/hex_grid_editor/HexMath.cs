using Godot;

/// <summary>
/// Utility class for hex grid coordinate math used by the editor.
/// Handles axial ↔ world ↔ offset conversions, bounds checking, and grid enumeration.
///
/// WHY THIS IS PORTED: The editor requires coordinate conversion to place scenes, detect
/// clicks, generate the guide grid, and calculate the border ring. These are editor/tooling
/// concerns. If your core library exposes equivalent axial↔world and offset↔axial functions
/// you can swap out the calls in HexGrid3D and HexGridEditorPlugin to use those instead,
/// then delete this file.
///
/// NOT INCLUDED: Distance() — unused by the editor (handled by your core library).
/// </summary>
public static class HexMath
{
    /// <summary>Convert axial coordinates to a local 3D world position (Y=0).</summary>
    public static Vector3 AxialToWorld(Vector2I axial, float hexSize, bool pointyTop)
    {
        float q = axial.X;
        float r = axial.Y;
        float x, z;

        if (pointyTop)
        {
            x = hexSize * Mathf.Sqrt(3f) * (q + r / 2f);
            z = hexSize * 1.5f * r;
        }
        else
        {
            x = hexSize * 1.5f * q;
            z = hexSize * Mathf.Sqrt(3f) * (r + q / 2f);
        }

        return new Vector3(x, 0f, z);
    }

    /// <summary>Convert a local 3D world position to the nearest axial coordinate.</summary>
    public static Vector2I WorldToAxial(Vector3 worldPos, float hexSize, bool pointyTop)
    {
        float q, r;

        if (pointyTop)
        {
            q = (Mathf.Sqrt(3f) / 3f * worldPos.X - 1f / 3f * worldPos.Z) / hexSize;
            r = (2f / 3f * worldPos.Z) / hexSize;
        }
        else
        {
            q = (2f / 3f * worldPos.X) / hexSize;
            r = (-1f / 3f * worldPos.X + Mathf.Sqrt(3f) / 3f * worldPos.Z) / hexSize;
        }

        return AxialRound(new Vector2(q, r));
    }

    /// <summary>Round fractional axial coordinates to the nearest hex using cube-coordinate constraint.</summary>
    public static Vector2I AxialRound(Vector2 axial)
    {
        float q = axial.X;
        float r = axial.Y;
        float s = -q - r;

        float rq = Mathf.Round(q);
        float rr = Mathf.Round(r);
        float rs = Mathf.Round(s);

        float qDiff = Mathf.Abs(rq - q);
        float rDiff = Mathf.Abs(rr - r);
        float sDiff = Mathf.Abs(rs - s);

        if (qDiff > rDiff && qDiff > sDiff)
            rq = -rr - rs;
        else if (rDiff > sDiff)
            rr = -rq - rs;

        return new Vector2I((int)rq, (int)rr);
    }

    /// <summary>Convert axial to offset (odd-r for pointy-top, odd-q for flat-top).</summary>
    public static Vector2I AxialToOffset(Vector2I axial, bool pointyTop)
    {
        if (pointyTop)
        {
            int col = axial.X + (axial.Y - (axial.Y & 1)) / 2;
            int row = axial.Y;
            return new Vector2I(col, row);
        }
        else
        {
            int col = axial.X;
            int row = axial.Y + (axial.X - (axial.X & 1)) / 2;
            return new Vector2I(col, row);
        }
    }

    /// <summary>Convert offset to axial coordinates.</summary>
    public static Vector2I OffsetToAxial(Vector2I offset, bool pointyTop)
    {
        if (pointyTop)
        {
            int q = offset.X - (offset.Y - (offset.Y & 1)) / 2;
            int r = offset.Y;
            return new Vector2I(q, r);
        }
        else
        {
            int q = offset.X;
            int r = offset.Y - (offset.X - (offset.X & 1)) / 2;
            return new Vector2I(q, r);
        }
    }

    /// <summary>Check if offset coordinates are within grid bounds.</summary>
    public static bool IsInBounds(Vector2I offset, int width, int height)
    {
        return offset.X >= 0 && offset.X < width && offset.Y >= 0 && offset.Y < height;
    }

    /// <summary>Get all axial coordinates for a rectangular grid.</summary>
    public static System.Collections.Generic.List<Vector2I> GetGridCoords(int width, int height, bool pointyTop)
    {
        var coords = new System.Collections.Generic.List<Vector2I>(width * height);
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++)
                coords.Add(OffsetToAxial(new Vector2I(col, row), pointyTop));
        return coords;
    }

    /// <summary>Get the 6 neighbouring axial coordinates.</summary>
    public static Vector2I[] GetNeighbors(Vector2I axial)
    {
        return new[]
        {
            axial + new Vector2I( 1,  0),
            axial + new Vector2I( 1, -1),
            axial + new Vector2I( 0, -1),
            axial + new Vector2I(-1,  0),
            axial + new Vector2I(-1,  1),
            axial + new Vector2I( 0,  1),
        };
    }
}
