#!/bin/sh

echo "Updating Suricata rule sources from Scirius"
docker exec scirius python /opt/scirius/manage.py shell -c "
from rules.models import Source
for s in Source.objects.all():
    s.update()
" 2>&1

echo "Exporting and reloading rules"
/usr/local/bin/suricata-reload-rules.sh
