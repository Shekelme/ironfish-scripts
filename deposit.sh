#!/bin/bash
# /etc/crontab:
# @reboot root bash /root/deposit.sh >> /var/log/ironfish_deposit.log
#
# background start:
# bash /root/deposit.sh >> /var/log/ironfish_deposit.log &
#
filename="$(basename $0)"

if [ ${filename} != "deposit.sh" ]; then
	echo -e '\033[0;31m'ERROR: This script must be named deposit.sh, your name is ${filename}'\033[0m'
	exit 1
fi

if [[ `pgrep -f ${filename}` != "$$" ]]; then
        echo "Another instance of the script already exist! Exiting"
	if [ -s "/var/run/${filename}.pid" ]; then echo -e "You can try to \033[0;31m kill -9 $(cat /var/run/${filename}.pid) \033[0m for killing the current process and then run a new one"; fi
        exit 1
fi

echo $$ > /var/run/${filename}.pid

dpkg -s bc > /dev/null 2>&1; if [ "$(echo $?)" != "0" ]; then apt-get -y install bc; fi

while true; do
# BALANCE=$(/usr/bin/yarn --cwd ${HOME}/ironfish/ironfish-cli/ ironfish accounts:balance $IRONFISH_WALLET | egrep "Amount available to spend" | awk '{ print $6 }' | sed 's/\,//')
BALANCE=`/usr/bin/yarn --cwd ${HOME}/ironfish/ironfish-cli/ ironfish accounts:balance $IRONFISH_WALLET | egrep "Amount available to spend" | awk '{ print $6 }' | sed 's/\,//'`
echo -e $(date): '\033[1;32m'"Available balance is ${BALANCE}"'\033[0m'
if (( $(echo "${BALANCE} >= 0.10000001" | bc -l) )); then
	REPEAT=$(echo ${BALANCE}/0.10000001 | bc -l | cut -d '.' -f1)
	if [ ! -z "${REPEAT}" ]; then
		for i in `seq ${REPEAT}`; do
			echo -e '\033[1;32m'"Transaction:"'\033[0m'
			/usr/bin/yarn --cwd ${HOME}/ironfish/ironfish-cli/ start deposit --confirm | tee /tmp/deposit-last.log
			echo -e '\033[0;31m'"-------------------------------------------------------------"'\033[0m'
			if [ ! -z "$(egrep -i "Insufficient" /tmp/deposit-last.log)" ]; then
				sleep 120
				break
			fi
		done
	fi
else
	sleep 5
fi
done
