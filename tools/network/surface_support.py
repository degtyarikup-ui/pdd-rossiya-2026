"""Participant support on actual built surfaces; paint/rails never lift a car."""
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree


class SurfaceSupport:
    def __init__(self, built):
        triangles, self.heights = [], []
        for surface in built.get("surfaces", []):
            if not surface.get("layer"):
                continue
            verts, indices = surface["verts"], surface["idx"]
            for i in range(0, len(indices), 3):
                triangles.append(Polygon([(verts[j * 2], verts[j * 2 + 1]) for j in indices[i:i + 3]]))
                self.heights.append(surface["y"])
        self.tree = STRtree(triangles)

    def height(self, x, z):
        hits = self.tree.query(Point(x, z), predicate="intersects")
        return max((self.heights[i] for i in hits), default=-0.15)
