#!/bin/bash
# /etc/crontab:
# @reboot root bash /root/deposit.sh >> /var/log/ironfish_deposit.log
#
# background start:
# bash /root/deposit.sh >> /var/log/ironfish_deposit.log &
#
echo -e 'Now we will create a folder under /var/run for current user - we need to do it every time after system reboot'
sudo mkdir /var/run/ironfish/
echo -e 'Now we will change the ownership for /var/run/ironfish'
sudo chown $USER:$USER /var/run/ironfish/

filename="$(basename $0)"

if [ ${filename} != "deposit.sh" ]; then
	echo -e '\033[0;31m'ERROR: This script must be named deposit.sh, your name is ${filename}'\033[0m'
	exit 1
fi

if [[ `pgrep -f ${filename}` != "$$" ]]; then
        echo "Another instance of the script already exist! Exiting"
	if [ -s "/var/run/ironfish/${filename}.pid" ]; then echo -e "You can try to \033[0;31m kill -9 $(cat /var/run/ironfish/${filename}.pid) \033[0m for killing the current process and then run a new one"; fi
        exit 1
fi

echo $$ > /var/run/ironfish/${filename}.pid

dpkg -s bc > /dev/null 2>&1; if [ "$(echo $?)" != "0" ]; then apt-get -y install bc; fi
dpkg -s parallel > /dev/null 2>&1; if [ "$(echo $?)" != "0" ]; then apt-get -y install parallel > /dev/null 2>&1; echo "Note: parallel package has been installed"; fi

while true; do
INSUFFICIENT_COUNT=0
# BALANCE=$(/usr/bin/yarn --cwd ${HOME}/ironfish/ironfish-cli/ ironfish accounts:balance $IRONFISH_WALLET | egrep "Amount available to spend" | awk '{ print $6 }' | sed 's/\,//')
BALANCE=`ironfish accounts:balance | egrep "Amount available to spend" | awk '{ print $6 }' | sed 's/\,//'`
echo ${BALANCE} > /tmp/.shadow_balance
echo -e $(date): '\033[1;32m'"Available balance is ${BALANCE}"'\033[0m'
if (( $(echo "${BALANCE} >= 0.10000001" | bc -l) )); then
	REPEAT=$(echo ${BALANCE}/0.10000001 | bc -l | cut -d '.' -f1)
	if [ ! -z "${REPEAT}" ]; then
		for i in `seq ${REPEAT}`; do
			if [ "$(($i % 10))" == 0 ] && [ "$i" != "1" ]; then
				echo $(ironfish accounts:balance | egrep "Amount available to spend" | awk '{ print $6 }' | sed 's/\,//') > /tmp/.shadow_balance 2>&1 &
			fi
			if (( $(echo $(cat /tmp/.shadow_balance) \>\= 0.10000001 | bc -l) )) && [ "$i" != "1" ]; then
				echo -e $(date): '\033[1;32m'Possible balance amount is about $(echo $(cat /tmp/.shadow_balance)-\(${i}-1\)*0.10000001 | bc | sed "/^\./ s/\./0\./")'\033[0m'
			fi
			echo -e '\033[1;32m'"Transaction:"'\033[0m'
			ironfish deposit --confirm | tee /tmp/deposit-last.log
			echo -e '\033[0;31m'"-------------------------------------------------------------"'\033[0m'
			sleep 200
			INSUFFICIENT_COUNT=0
			if [ ! -z "$(egrep -i "Insufficient" /tmp/deposit-last.log)" ]; then
				((INSUFFICIENT_COUNT++))
				echo "Insufficient funds error count is ${INSUFFICIENT_COUNT}"
					if [ "${INSUFFICIENT_COUNT}" == "5" ] && [ -z "$(ps aux | egrep "accounts:rescan" | egrep -v grep | grep ironfish)" ] && [ "${1}" == "rescan-allowed" ]; then
						echo -e '\033[0;31m'Too many Insufficient funds errors. Rescan will start now.'\033[0m'
						ironfish accounts:rescan
						INSUFFICIENT_COUNT=0
						break
					fi
				sleep 200
			fi
			if [ ! -z "$(egrep -i "An error occurred while sending the transaction" /tmp/deposit-last.log)" ]; then
				# It means that network is down, script will sleep for 30 minutes until next try
				sleep 1800
				break
			fi
		done
	fi
else
	sleep 200
fi
done
