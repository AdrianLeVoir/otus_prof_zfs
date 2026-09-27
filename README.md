# Домашнее задание: Практические навыки работы с ZFS

## Формулировка задания

1. **Определить алгоритм с наилучшим сжатием:**
   - определить, какие алгоритмы сжатия поддерживает ZFS (gzip, zle, lzjb, lz4);
   - создать 4 файловые системы, на каждой применить свой алгоритм сжатия;
   - для сжатия использовать текстовый файл или группу файлов.
2. **Определить настройки пула:**
   - с помощью `zpool import` собрать pool ZFS;
   - командами `zfs` определить: размер хранилища, тип пула, `recordsize`, сжатие, контрольную сумму.
3. **Работа со снапшотами:**
   - скопировать файл из «удалённой» директории;
   - восстановить файл локально через `zfs receive`;
   - найти зашифрованное сообщение в файле `secret_message`.

## Стенд

| Параметр | Значение |
|---|---|
| Гипервизор | Proxmox VE 9.1.6 |
| ВМ | 4 vCPU / 6 GB RAM |
| ОС | Ubuntu 24.04.3 LTS, ядро 6.8.0-142-generic |

Все команды выполнялись от `root` (`sudo -i`) и логировались утилитой `script`
(см. каталог `logs/`). Скрипт воспроизведения стенда — `setup.sh`.

---

## 1. Алгоритм с наилучшим сжатием

Поддерживаемые ZFS алгоритмы сжатия: `on/off`, **`lzjb`**, **`lz4`**, **`gzip-N`**, **`zle`**
(в 2.2 дополнительно `zstd`). Создаём 4 пула-зеркала и задаём на каждом свой алгоритм:

```bash
zpool create otus1 mirror /dev/sdb /dev/sdc
zpool create otus2 mirror /dev/sdd /dev/sde
zpool create otus3 mirror /dev/sdf /dev/sdg
zpool create otus4 mirror /dev/sdh /dev/sdi

zfs set compression=lzjb   otus1
zfs set compression=lz4    otus2
zfs set compression=gzip-9 otus3
zfs set compression=zle    otus4

zfs get compression
```

```
NAME   PROPERTY     VALUE           SOURCE
otus1  compression  lzjb            local
otus2  compression  lz4             local
otus3  compression  gzip-9          local
otus4  compression  zle             local
```

Во все пулы копируются **одни и те же** текстовые файлы
(`big.txt` — 6.5 MB, `words.txt` — 4.2 MB; итого ~10.7 MB):

```bash
for p in otus1 otus2 otus3 otus4; do cp big.txt words.txt /$p/; done
zfs list ; zfs get compressratio
```

### Результаты

| Пул | Алгоритм | Сжатие (compressratio) | Занято (USED) |
|---|---|---|---|
| otus1 | `lzjb` | 1.61x | 6.54M |
| otus2 | `lz4` | 1.77x | 5.97M |
| **otus3** | **`gzip-9`** | **3.02x** | **3.54M** |
| otus4 | `zle` | 1.01x | 10.4M |

```
NAME    USED  AVAIL  REFER  MOUNTPOINT
otus1  6.54M   345M  6.44M  /otus1
otus2  5.97M   346M  5.87M  /otus2
otus3  3.54M   348M  3.44M  /otus3
otus4  10.4M   342M  10.3M  /otus4

NAME   PROPERTY       VALUE  SOURCE
otus1  compressratio  1.61x  -
otus2  compressratio  1.77x  -
otus3  compressratio  3.02x  -
otus4  compressratio  1.01x  -
```

**Вывод:** наилучшее сжатие даёт **`gzip-9`** (3.02x). `lz4` быстрее и почти не нагружает
CPU, давая умеренное сжатие (1.77x). `lzjb` — устаревший, слабее `lz4`. `zle`
сжимает только нулевые последовательности (1.01x на тексте). Для общего случая —
баланс `lz4`, для максимума места — `gzip-9`.

---

## 2. Настройки пула (импорт)

```bash
wget -O archive.tar.gz --no-check-certificate \
  'https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download'
tar -xzvf archive.tar.gz          # → zpoolexport/filea, zpoolexport/fileb

zpool import -d zpoolexport/      # обнаружение
zpool import -d zpoolexport/ otus # импорт
zpool status
```

```
  pool: otus
 state: ONLINE
config:
	NAME                                    STATE     READ WRITE CKSUM
	otus                                    ONLINE       0     0     0
	  mirror-0                              ONLINE       0     0     0
	    /root/zfs_import/zpoolexport/filea  ONLINE       0     0     0
	    /root/zfs_import/zpoolexport/fileb  ONLINE       0     0     0
```

### Требуемые настройки

| Параметр | Команда | Значение |
|---|---|---|
| Размер хранилища | `zfs get available otus` | 350M (пул `size` = 480M) |
| Тип пула | `zpool status` | **mirror** (RAID1, `mirror-0`) |
| `recordsize` | `zfs get recordsize otus` | **128K** |
| Сжатие | `zfs get compression otus` | **zle** |
| Контрольная сумма | `zfs get checksum otus` | **sha256** |

**Вывод:** импортированный пул `otus` — зеркало из двух файлов-устройств
(«тип pool — mirror»), размер 480 MB, `recordsize=128K`, сжатие `zle`,
контрольная сумма `sha256` (наиболее надёжная из доступных).

---

## 3. Работа со снапшотом и поиск сообщения

```bash
wget -O otus_task2.file --no-check-certificate \
  'https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI&export=download'

zfs receive otus/test@today < otus_task2.file      # восстановление из снапшота
zfs list -r otus
zfs list -t snapshot
find /otus/test -name secret_message
```

```
NAME              USED  AVAIL  REFER  MOUNTPOINT
otus/test         2.83M   347M  2.83M  /otus/test
otus/test@today     0B      -  2.83M  -

/otus/test/task1/file_mess/secret_message
```

Содержимое найденного файла:

```
$ cat /otus/test/task1/file_mess/secret_message
https://otus.ru/lessons/linux-hl/
```

**Вывод:** поток `zfs send` успешно принят командой `zfs receive` в датасет
`otus/test`; в снапшоте `otus/test@today` найдено «зашифрованное» сообщение —
ссылка на курс **https://otus.ru/lessons/linux-hl/**.

---

## Итоговое состояние

```
$ zpool list
NAME    SIZE  ALLOC   FREE  ...  HEALTH
otus    480M  4.89M   475M  ...  ONLINE
otus1   480M  6.54M   473M  ...  ONLINE
otus2   480M  5.97M   474M  ...  ONLINE
otus3   480M  3.54M   476M  ...  ONLINE
otus4   480M  10.4M   470M  ...  ONLINE
```

## Логи (`script`)

| Файл | Содержимое |
|---|---|
| `logs/zfs_task1_pools.log` | создание 4 пулов и алгоритмов сжатия |
| `logs/zfs_task1_compression.log` | тест сжатия и итоговая таблица |
| `logs/zfs_task2_import.log` | импорт пула `otus` и все его настройки |
| `logs/zfs_task3_snapshot.log` | `zfs receive` и поиск `secret_message` |
| `logs/zfs_final_state.log` | итоговое состояние (`zpool`, `zfs`, `lsblk`) |

## Файлы репозитория

- `README.md` — этот отчёт;
- `setup.sh` — скрипт, воспроизводящий стенд и все шаги задания;
- `logs/` — логи выполнения, снятые утилитой `script`.
