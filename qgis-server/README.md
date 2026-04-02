# QGIS Server (Railway Service)

Dieser Ordner ist für einen **zweiten Railway Service** gedacht (neben der Admin-Webapp).

## Ziel

- QGIS Desktop dient zum Erstellen/Stylen der Layer in einem Projekt (`.qgz`/`.qgs`)
- QGIS Server veröffentlicht dieses Projekt als **WMS/WFS**
- Die Admin-Webapp ruft QGIS über den Proxy `GET /api/qgis/wms` ab

## Railway Setup (empfohlen)

1. Railway → neues Projekt oder bestehendes Projekt → **New Service** → **Deploy from GitHub repo**
2. **Root Directory** für diesen Service: `qgis-server`
3. **Variables** setzen:
   - `QGIS_PROJECT_FILE=/data/project.qgz`
4. **Volume** hinzufügen:
   - Mount Path: `/data`
   - Dort später `project.qgz` ablegen (z. B. per SFTP/Upload-Workflow oder per Git/Build-Asset je nach eurem Prozess)

## QGIS URL (für die Admin-Webapp)

In der Admin-Webapp (Service 1) setzt ihr:

- `QGIS_WMS_BASE_URL` auf die **interne** URL des QGIS Services, z. B. `http://<qgis-service>:80/ows`

Der konkrete interne Hostname hängt von Railway ab (Service-Discovery / private networking).

## Referenzen

- QGIS Server Container deployment: [QGIS Doku](https://docs.qgis.org/3.28/en/docs/server_manual/containerized_deployment.html)
- Offizielles Docker Image: [qgis/qgis-server Tags](https://hub.docker.com/r/qgis/qgis-server/tags)

