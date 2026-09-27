#!/usr/bin/env bash
# Запускать от root:  sudo bash setup.sh
# Ожидается 8 свободных дисков /dev/sdb.. /dev/sdi по 512 MB.
set -euo pipefail

echo "===> 1. Установка ZFS"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y zfsutils-linux

echo "===> 2. 4 пула-зеркала с разными алгоритмами сжатия"
zpool create -f otus1 mirror /dev/sdb /dev/sdc
zpool create -f otus2 mirror /dev/sdd /dev/sde
zpool create -f otus3 mirror /dev/sdf /dev/sdg
zpool create -f otus4 mirror /dev/sdh /dev/sdi
zfs set compression=lzjb   otus1
zfs set compression=lz4    otus2
zfs set compression=gzip-9 otus3
zfs set compression=zle    otus4
zfs get compression

echo "===> 3. Тест сжатия одним и тем же набором файлов"
mkdir -p /tmp/zfstest && cd /tmp/zfstest
[ -f big.txt ]   || curl -sSL -o big.txt   https://norvig.com/big.txt
[ -f words.txt ] || curl -sSL -o words.txt https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt
for p in otus1 otus2 otus3 otus4; do cp big.txt words.txt /$p/; done
sync; sleep 3
zfs list
zfs get compressratio

echo "===> 4. Импорт готового пула otus"
mkdir -p /root/zfs_import && cd /root/zfs_import
wget -q -O archive.tar.gz --no-check-certificate \
  'https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download'
tar -xzvf archive.tar.gz
zpool import -d zpoolexport/ otus
zpool status
zfs get available,readonly,recordsize,compression,checksum otus

echo "===> 5. Восстановление из снапшота и поиск сообщения"
wget -q -O otus_task2.file --no-check-certificate \
  'https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI&export=download'
zfs receive otus/test@today < otus_task2.file
find /otus/test -name secret_message -exec cat {} \;

echo "===> Готово."
