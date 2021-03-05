#!/bin/bash

set -e
trap 'echo ERROR on line number $LINENO' ERR

repo="https://github.com/bing281/graphs1090"
ipath=/usr/share/graphs1090
install=0

commands="git rrdtool collectd"
packages="git rrdtool collectd-core"

mkdir -p $ipath/installed
mkdir -p /var/lib/graphs1090/scatter

for CMD in $commands
do
	if ! command -v "$CMD" &>/dev/null
	then
		install=1
		touch $ipath/installed/$i
	fi
done

if grep -E 'stretch|jessie|buster' /etc/os-release -qs
then
	if ! dpkg -s libpython2.7 2>/dev/null | grep 'Status.*installed' &>/dev/null
	then
		apt-get update
		apt-get install -y 'libpython2.7'
		update_done=yes
	fi
else
	if ! dpkg -s libpython2.7 2>/dev/null | grep 'Status.*installed' &>/dev/null \
		|| ! dpkg -s libpython3.7 2>/dev/null | grep 'Status.*installed' &>/dev/null \
		|| ! dpkg -s libpython3.8 2>/dev/null | grep 'Status.*installed' &>/dev/null
	then
		apt-get update
		apt-get install -y 'libpython2.7'
		apt-get install -y 'libpython3.7'
		apt-get install -y 'libpython3.8'
        update_done=yes
	fi
fi

if [[ $install == "1" ]]
then
	echo "------------------"
	echo "Installing required packages: $packages"
	echo "------------------"
	if [[ $update_done != "yes" ]]; then
		apt-get update
	fi
	#apt-get upgrade -y
	if apt-get install -y --no-install-suggests --no-install-recommends $packages
	then
		echo "------------------"
		echo "Packages successfully installed!"
		echo "------------------"
	else
		echo "------------------"
		echo "Failed to install required packages: $packages"
		echo "Exiting ..."
		exit 1
	fi
fi

# make sure commands are available if they were just installed
hash -r


if [[ "$1" == "test" ]]
then
	true
elif { cd "$ipath/git" &>/dev/null && git fetch origin master && git reset --hard FETCH_HEAD; } || { cd /tmp && rm -rf "$ipath/git" && git clone -b master --depth 1 "$repo" "$ipath/git" && cd $ipath/git; }; then
    true
elif wget --timeout=30 -q -O /tmp/master.zip $repo/archive/master.zip && unzip -q -o master.zip
then
	cd /tmp/graphs1090-master
else
	echo "Unable to download files, exiting! (Maybe try again?)"
	exit 1
fi

cp dump1090.db dump1090.py system_stats.py LICENSE $ipath
cp *.sh $ipath
cp malarky.service $ipath
chmod u+x $ipath/*.sh
if ! grep -e 'system_stats' -qs /etc/collectd/collectd.conf &>/dev/null; then
	cp /etc/collectd/collectd.conf /etc/collectd/collectd.conf.graphs1090 &>/dev/null || true
	cp collectd.conf /etc/collectd/collectd.conf
	echo "------------------"
	echo "Overwriting /etc/collectd/collectd.conf, the old file has been moved to /etc/collectd/collectd.conf.graphs1090"
	echo "------------------"
fi
sed -i -e 's/XFF.*/XFF 0.8/' /etc/collectd/collectd.conf
sed -i -e 's/skyview978/skyaware978/' /etc/collectd/collectd.conf
rm -f /etc/cron.d/cron-graphs1090
cp -r html $ipath
cp -n default /etc/default/graphs1090
cp default $ipath/default-config
cp collectd.conf $ipath/default-collectd.conf
cp service.service /lib/systemd/system/graphs1090.service
cp nginx-graphs1090.conf $ipath

# bust cache for all css and js files
sed -i -e "s/__cache_version__/$(date +%s | tail -c5)/g" $ipath/html/index.html

if [ -d /etc/lighttpd/conf.d/ ] && ! [ -d /etc/lighttpd/conf-enabled/ ] && ! [ -d /etc/lighttpd/conf-available ] && command -v lighttpd &>/dev/null
then
    ln -snf /etc/lighttpd/conf.d /etc/lighttpd/conf-enabled
    mkdir -p /etc/lighttpd/conf-available
fi
if [ -d /etc/lighttpd/conf-enabled/ ] && [ -d /etc/lighttpd/conf-available ] && command -v lighttpd &>/dev/null
then
    lighttpd=yes
fi

if [[ $lighttpd == yes ]]; then
    cp 88-graphs1090.conf /etc/lighttpd/conf-available
    ln -snf /etc/lighttpd/conf-available/88-graphs1090.conf /etc/lighttpd/conf-enabled/88-graphs1090.conf
    if ! grep -qs -E -e '^[^#]*"mod_alias"' /etc/lighttpd/lighttpd.conf /etc/lighttp/conf-enabled/* /etc/lighttpd/external.conf; then
        echo 'server.modules += ( "mod_alias" )' > /etc/lighttpd/conf-available/07-mod_alias.conf
        ln -s -f /etc/lighttpd/conf-available/07-mod_alias.conf /etc/lighttpd/conf-enabled/07-mod_alias.conf
    else
        rm -f /etc/lighttpd/conf-enabled/07-mod_alias.conf
    fi
fi

SYM=/usr/share/graphs1090/data-symlink
mkdir -p $SYM
if [ -f /run/dump1090-fa/stats.json ]; then
    ln -snf /run/dump1090-fa $SYM/data
    sed -i 's?URL "http://local.*?URL "http://localhost/dump1090-fa"?' /etc/collectd/collectd.conf
elif [ -f /run/readsb/stats.json ]; then
    ln -snf /run/readsb $SYM/data
    sed -i 's?URL "http://local.*?URL "http://localhost/radar"?' /etc/collectd/collectd.conf
elif [ -f /run/adsbexchange-feed/stats.json ]; then
    ln -snf /run/adsbexchange-feed $SYM/data
    sed -i 's?URL "http://local.*?URL "http://localhost/tar1090"?' /etc/collectd/collectd.conf
elif [ -f /run/dump1090/stats.json ]; then
    ln -snf /run/dump1090 $SYM/data
    sed -i 's?URL "http://local.*?URL "http://localhost/dump1090"?' /etc/collectd/collectd.conf
elif [ -f /run/dump1090-mutability/stats.json ]; then
    ln -snf /run/dump1090-mutability $SYM/data
    sed -i 's?URL "http://local.*?URL "http://localhost/dump1090"?' /etc/collectd/collectd.conf
else
	echo --------------
	echo "Non-standard configuration detected, you need to change the data URL in /etc/collectd/collectd.conf!"
	echo --------------
fi

SYM=/usr/share/graphs1090/978-symlink
mkdir -p $SYM
if [ -f /run/skyaware978/aircraft.json ]; then
    ln -snf /run/skyaware978 $SYM/data
    sed -i 's?URL_978.*?URL_978 "file:///usr/share/graphs1090/978-symlink"?' /etc/collectd/collectd.conf
elif wget -O /dev/null http://localhost/skyaware978/data/aircraft.json 2>/dev/null; then
    sed -i 's?URL_978.*?URL_978 "http://localhost/skyaware978"?' /etc/collectd/collectd.conf
elif wget -O /dev/null http://localhost/978/data/aircraft.json 2>/dev/null; then
    sed -i 's?URL_978.*?URL_978 "http://localhost/978"?' /etc/collectd/collectd.conf
fi

if grep jessie /etc/os-release >/dev/null
then
	echo --------------
	echo "Some features are not available on jessie!"
	echo --------------
	sed -i -e 's/ADDNAN/+/' -e 's/TRENDNAN/TREND/' -e 's/MAXNAN/MAX/' -e 's/MINNAN/MIN/' $ipath/graphs1090.sh
	sed -i -e '/axis-format/d' $ipath/graphs1090.sh
fi


mkdir -p /var/lib/collectd/rrd/localhost/dump1090-localhost

if [[ $lighttpd == yes ]]; then
    systemctl restart lighttpd
fi

systemctl enable collectd &>/dev/null
if [[ -f /usr/share/graphs1090/noMalarky ]]; then
    systemctl restart collectd
else
    bash $ipath/malarky.sh
fi

systemctl enable graphs1090
systemctl restart graphs1090

#fix readonly remount logic in fr24feed update script
sed -i -e 's?$(mount | grep " on / " | grep rw)?{ mount | grep " on / " | grep rw; }?' /usr/lib/fr24/fr24feed_updater.sh &>/dev/null || true

echo --------------
echo --------------
echo "All done! Graphs available at http://$(ip route | grep -m1 -o -P 'src \K[0-9,.]*')/graphs1090"
echo "It may take up to 10 minutes until the first data is displayed"


if command -v nginx &>/dev/null
then
	echo --------------
	echo "To configure nginx for graphs1090, please add the following line(s) in the server {} section:"
	echo "include /usr/share/graphs1090/nginx-graphs1090.conf;"
fi
