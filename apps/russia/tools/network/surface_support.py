"""Participant support on actual built surfaces; paint/rails never lift a car."""
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree


class SurfaceSupport:
    def __init__(self, built):
        triangles, self.heights, self.corners = [], [], []
        for surface in built.get("surfaces", []):
            if not surface.get("layer") and not surface.get("support"):
                continue
            verts, indices = surface["verts"], surface["idx"]
            for i in range(0, len(indices), 3):
                triangles.append(Polygon([(verts[j * 2], verts[j * 2 + 1]) for j in indices[i:i + 3]]))
                ids = indices[i:i + 3]
                self.corners.append([(verts[j * 2], verts[j * 2 + 1]) for j in ids])
                self.heights.append([surface.get("heights", [])[j] if "heights" in surface else surface["y"] for j in ids])
        self.tree = STRtree(triangles)

    def height(self, x, z):
        hits = self.tree.query(Point(x, z), predicate="intersects")
        def height_at(i):
            a, b, c = self.corners[i]
            ha, hb, hc = self.heights[i]
            if ha == hb == hc:
                return ha
            det = (b[1]-c[1])*(a[0]-c[0]) + (c[0]-b[0])*(a[1]-c[1])
            if abs(det) < 1e-12:
                return max(ha, hb, hc)
            u = ((b[1]-c[1])*(x-c[0]) + (c[0]-b[0])*(z-c[1])) / det
            v = ((c[1]-a[1])*(x-c[0]) + (a[0]-c[0])*(z-c[1])) / det
            return ha*u + hb*v + hc*(1-u-v)
        return max((height_at(i) for i in hits), default=-0.15)
