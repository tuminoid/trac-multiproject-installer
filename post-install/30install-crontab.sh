# Install crontab for Trac
# Author: Tuomo Tanskanen <tumi@tumi.fi>
# LICENSE: See 'LICENSE' file

cat <<EOF >$TRAC_INSTALL/www-data.cron
# Generate project activities into database
* */5 * * * source /etc/trac/variables; nice python $trac_root/scripts/cron/project_activity_update.py

# Goes through projects to see how much resources they consumes
* */2 * * * source /etc/trac/variables; $trac_root/scripts/cron/storageusage.sh

# Do indexing for projects. Needed for explore projects feature.
0 6,18 * * * source /etc/trac/variables; nice python $trac_root/scripts/cron/generate_project_user_visibility.py 2>&1 > /tmp/generate_project_user_visibility.log
EOF

crontab -u www-data $TRAC_INSTALL/www-data.cron
