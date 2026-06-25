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
- 路名/地名标注（需字体 glyphs）作后续阶段。

---

# 等高线数据管线（DEM → 等高线 → PMTiles）

用 GDAL 由 Copernicus GLO-30 DEM 生成等高线矢量瓦片。Windows 无 GDAL，用 micromamba 装 conda-forge GDAL（免管理员）。

## 一、装 GDAL（一次性）
```bash
cd tools
# micromamba 单文件（github 下载，走代理）
curl -L -x http://127.0.0.1:10809 -o micromamba.exe \
  https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-win-64
export HTTPS_PROXY=http://127.0.0.1:10809 MAMBA_ROOT_PREFIX="$(pwd)/mamba"
./micromamba.exe create -p "$(pwd)/gdalenv" -c conda-forge gdal -y
```
> GDAL 3.13 自带 PMTiles 驱动；二进制在 `gdalenv/Library/bin`，数据在 `gdalenv/Library/share/{gdal,proj}`。

## 二、生成某区域等高线
```bash
export GDAL_DATA="$(pwd)/gdalenv/Library/share/gdal" PROJ_LIB="$(pwd)/gdalenv/Library/share/proj"
BIN="$(pwd)/gdalenv/Library/bin"

# 1) 下 Copernicus GLO-30 DEM 瓦片（AWS 开放数据，按 bbox 选 1°×1° 块，无需登录）
#    命名 Copernicus_DSM_COG_10_N{lat2}_00_E{lon3}_00_DEM，例（本溪 N40-41 / E123-125 共 6 块）：
for n in N40_00_E123 N40_00_E124 N40_00_E125 N41_00_E123 N41_00_E124 N41_00_E125; do
  name="Copernicus_DSM_COG_10_${n}_00_DEM"
  curl -L -x http://127.0.0.1:10809 -o "dem/${name}.tif" \
    "https://copernicus-dem-30m.s3.amazonaws.com/${name}/${name}.tif"
done

# 2) 合并 → 10m 等高线 → PMTiles（idx=1 标记 50m 计曲线，文件名须含 contour 供 App 识别）
"$BIN/gdalbuildvrt" dem.vrt dem/*.tif
"$BIN/gdal_contour" -a elev -i 10 dem.vrt contour.gpkg
"$BIN/ogr2ogr" -f PMTiles 区域名-contour.pmtiles contour.gpkg \
  -dialect SQLITE -sql "SELECT *, (CAST(elev AS integer)%50=0) AS idx FROM contour" \
  -nln contour -dsco MINZOOM=11 -dsco MAXZOOM=14
```
> 注意：重跑前先删旧的 `*-contour.pmtiles*` 临时文件，否则 PMTiles 驱动报 "table already exists"。

## 三、导入与使用
导入 `区域名-contour.pmtiles`（文件名含 `contour`）→ 地图页/详情页右侧「等高线」开关 → 青色等高线叠在任何底图上（10m 细线 + 50m 计曲线加粗）。
