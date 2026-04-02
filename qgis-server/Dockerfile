FROM qgis/qgis-server:stable-trixie

# Railway setzt PORT. QGIS Image lauscht standardmäßig auf 80 (nginx).
# Wir behalten 80 und setzen PORT nur für Healthchecks/Infos in Logs nicht um.

# QGIS Server Projektdatei kommt per ENV:
# - QGIS_PROJECT_FILE=/data/project.qgz (oder .qgs)
# Daten sollten über ein Railway Volume nach /data gemountet werden.

ENV QGIS_SERVER_LOG_STDERR=1 \
    QGIS_SERVER_LOG_LEVEL=2

# Default: startet den Server aus dem Base Image (nginx + qgis-server fcgi)
