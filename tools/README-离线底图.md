# 离线矢量底图数据管线（电脑侧）

用 [planetiler](https://github.com/onthegomap/planetiler) 把 OSM 数据生成**矢量 PMTiles**（OpenMapTiles schema），导入 App 后即可离线渲染底图。坐标系 WGS-84。

## 前置
- **Java 21+**（`java -version` 确认）
- 下载 `planetiler.jar`：<https://github.com/onthegomap/planetiler/releases>（取 `planetiler.jar`）

## 一、生成 PMTiles

### 方式 A：planetiler 自带下载（已知区域，最省事）
```bash
java -Xmx4g -jar planetiler.jar \
  --download --area=<area> \
  --maxzoom=14 \
  --output=basemap.pmtiles
```
- `<area>` 用 Geofabrik 区域名（如某省/地区）。矢量瓦片 maxzoom=14 即可，App 端会过缩放到 z16，无需更高。
- 产物 `basemap.pmtiles`（OpenMapTiles schema，含 water/landcover/landuse/park/transportation/building/boundary 等图层，正是 App 离线样式所用）。

### 方式 B：自备 .osm.pbf（精确小区域）
1. 从 Geofabrik 下载省级 `.osm.pbf`；
2. 用 [osmium](https://osmcode.org/osmium-tool/) 按 bbox 裁剪：
   ```bash
   osmium extract -b minLon,minLat,maxLon,maxLat region.osm.pbf -o small.osm.pbf
   ```
3. 生成：
   ```bash
   java -Xmx4g -jar planetiler.jar --osm-path=small.osm.pbf --maxzoom=14 --output=basemap.pmtiles
   ```

> 体积参考：山区一个地市级区域 maxzoom14 通常几十~一两百 MB。区域越大、级别越高，包越大。

## 二、导入手机
1. 把 `basemap.pmtiles`（可重命名为有意义的名字，如 `赤峰.pmtiles`）传到手机：AirDrop / 微信传文件 / iCloud 文件。
2. App →「我的 → 离线地图 → 导入 .pmtiles」选择该文件。
3. 地图页右上「图层」→ 选「离线 · 赤峰」→ 切到离线矢量底图。**开飞行模式验证**底图仍渲染。

## 说明 / 现状
- 首版离线矢量样式**仅几何**（地形/水系/道路/步道/建筑/边界），**暂无文字标注**（地名/路名）——标注需字体 glyphs，作后续阶段。
- 路网（OSM `path/track/footway`）已在样式中以棕色虚线呈现。
- 等高线（DEM→gdal_contour→瓦片）属后续阶段，单独并入。
