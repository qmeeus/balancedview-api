#!/bin/sh

if [ -z "$FLASK_RUN_PORT" ]; then
    echo "FLASK_RUN_PORT undefined." && exit 1
fi

for fn in ibm-credentials.env news_apikey; do
  fullname=api/resources/$fn
  if ! [ -f $fullname ]; then
    echo "Missing file: $fullname" && exit 1
  fi
done

python_path=$(which python)

cat <<EOF > /tmp/scheduler.txt
$(env | sed 's:HOME=.*:HOME=/api:')
SHELL=/bin/bash
@reboot sleep 60 && $python_path -m api.data_provider >> /var/log/cron.log 2>&1
0 6,12,18 * * * $python_path -m api.data_provider >> /var/log/cron.log 2>&1
# This extra line makes it a valid cron"
EOF

crontab /tmp/scheduler.txt

printf "Start cron... "
bash -c cron
printf "$(service cron status)\n"

echo "Starting API server"
gunicorn -w3 -k gevent --timeout 120 --bind=0.0.0.0:5000 api.wsgi
