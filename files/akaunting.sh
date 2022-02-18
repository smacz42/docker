#!/bin/bash -e

a2enmod rewrite

do_start=
do_shell=
do_setup=

while [ $# -gt 0 ]; do
    case "$1" in
        --start)
            do_start=true
            ;;
        --shell)
            do_start=false
            do_shell=true
            ;;
        --setup)
            do_setup=true
            do_start=true
            ;;
    esac
    shift
done

# Here we rsync the files over from /usr/local/src to /var/www/html after the container
# starts up. This is because if any of the directories are mounted as bind mountpoints,
# they would be mounted on top of the already-existing files, and render them unable to
# be accessed (e.g. /var/www/html/modules). This ensures that not only do we copy the
# files to the appropriate directories, but it also ensures that the correct modules are
# present, by ensuring that the modules that are present in that directory are the ones
# That are compatible with this version of the container. Note that we also pass the
# --remove-source-files flag here so that all of the files in /usr/local/src get removed
# just in case we're working on a space-constrained system.
rsync --remove-source-files -av /usr/local/src /var/www/html

# Let's do the chmod/chown up here before the install
chmod -R u=rwX,g=rX,o=rX /var/www/html
chown -R www-data:root /var/www/html

mkdir -p storage/framework/{sessions,views,cache}
mkdir -p storage/app/uploads

if [ "$do_setup" -o "$AKAUNTING_SETUP" == "true" ]; then
    retry_for=30
    retry_interval=5
    while sleep $retry_interval; do
        if php artisan install \
            --db-host=$DB_HOST \
            --db-name=$DB_DATABASE \
            --db-username=$DB_USERNAME \
            "--db-password=$DB_PASSWORD" \
            --db-prefix=$DB_PREFIX \
            "--company-name=$COMPANY_NAME" \
            "--company-email=$COMPANY_EMAIL" \
            "--admin-email=$ADMIN_EMAIL" \
            "--admin-password=$ADMIN_PASSWORD" \
            "--locale=$LOCALE" --no-interaction; then break
        else
            if [ $retry_for -le 0 ]; then
                echo "Unable to find database!" >&2
                exit 1
            fi
            (( retry_for -= retry_interval ))
        fi
    done
else
    unset COMPANY_NAME COMPANY_EMAIL ADMIN_EMAIL ADMIN_PASSWORD
fi

# Also chmod/chown after the install, why not.
chmod -R u=rwX,g=rX,o=rX /var/www/html
chown -R www-data:root /var/www/html

if [ "$do_start" ]; then
    exec docker-php-entrypoint apache2-foreground
elif [ "$do_shell" ]; then
    exec /bin/bash -li
fi
