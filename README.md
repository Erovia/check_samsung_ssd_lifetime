# Check the lifetime of Samsung SSDs on Linux

## Usage

Run any of the scripts either as `root` or regular user.  
For the latter, provide `sudo` password when prompted.  
Pass the `/dev` path of the Samsung SSD as the first and only positional argument.

```
$ bash/check_samsung_ssd_lifetime.bash /dev/nvme0
Device: /dev/nvme0
Model: PM9A1 NVMe Samsung 512GB
Serial number: XXXXXXXXXXXXX
Power on time: 408 hours
Data written:
    MB: 8,326,637 [8,131,482 MiB]
    GB: 8,326 [7,940 GiB]
    TB: 8 [7 TiB]
Mean write rate:
    MB/hr: 20,408
Available spare capacity: 100%
Estimated drive health: 98%
```

```
$ python/check_samsung_ssd_lifetime.py /dev/sda
Device: /dev/sda
Model: Samsung SSD 850 EVO 500GB
Serial number: XXXXXXXXXXXXXX
Power on time: 7,177 hours
Data written:
    MB: 41,621,907,496 [40,646,394,040 MiB]
    GB: 41,621,907 [39,693,744 GiB]
    TB: 41,621 [38,763 TiB]
Mean write rate:
    MB/hr: 5,799,346
Estimated drive health: 95%
```

## Details

The scripts in this repository are written in different languages but are functionally identical.  
Their only external dependency is the `smartctl` command from the `smartmontools` package.

## Credits

This project started as a rewrite of J. D. G. Leaver's Bash script.  
Unfortunately, his website seems to be no longer online, but can still be [viewed on the Internet Archive's Wayback Machine](https://web.archive.org/web/20170907062210/http://www.jdgleaver.co.uk/blog/2014/05/23/samsung_ssds_reading_total_bytes_written_under_linux.html).  
The original script is also immortalised [on the AskUbuntu forums](https://askubuntu.com/a/865793).
