### |P|P|S|S| - (Distributed) Parallel Processing Shell Script

* I've moved this project from Google code to Github. I've not updated this code since 2011. It was a hobby and an excersise in Bash Shell Scripting. It has served it's purpose for me.*

PPSS is a Bash shell script that executes commands, scripts or programs in parallel. It is designed to make full use of current multi-core CPUs. It will detect the number of available CPUs and start a separate job for each CPU core. It will also use hyper threading by default. 

PPSS can be run on multiple hosts, processing a single group of items, like a cluster. 

PPSS provides you with examples that will make it obvious how it is used:

    bash-3.2$ ppss
    |P|P|S|S| Distributed Parallel Processing Shell Script 2.60

    usage: ./ppss [ -d <sourcedir> | -f <sourcefile> ]  [ -c '<command> "$ITEM"' ]
                     [ -C <configfile> ] [ -j ] [ -l <logfile> ] [ -p <# jobs> ]
                     [ -D <delay> ] [ -h ] [ --help ] [ -r ] 
    
    Examples:
                     ./ppss -d /dir/with/some/files -c 'gzip '
                     ./ppss -d /dir/with/some/files -c 'cp "$ITEM" /tmp' -p 2
                     ./ppss -f <file> -c 'wget -q -P /destination/directory "$ITEM"' -p 10



Basically, just provide PPSS with a source of items (a directory with files, for example) and a command that must be applied to these items.

For a quick demonstration of it's standalone usage, see the video below.

<wiki:video width=600px url="http://www.youtube.com/watch?v=32PwsARbePw"/>

A bit more advanced (better quality): 

<wiki:video width=600px url="http://www.youtube.com/watch?v=AdwZlW1eZ6A"/>

PPSS will take a list of items as input. Items can be files within a directory or entries in a text file. PPSS 
executes a user-specified command for each item in this list. The item is supplied as an argument to this command. At any point in time, there are never more items processed in parallel as there are cores available.

An example how this script is used:


    user@host:~/ppss$ ./ppss.sh -d /wavs -c './encode.sh ' 
    Mar 30 23:21:10: INFO  =========================================================
    Mar 30 23:21:10: INFO                         |P|P|S|S|                         
    Mar 30 23:21:10: INFO  Distributed Parallel Processing Shell Script version 2.18
    Mar 30 23:21:10: INFO  =========================================================
    Mar 30 23:21:10: INFO  Hostname:	Core i7
    Mar 30 23:21:10: INFO  ---------------------------------------------------------
    Mar 30 23:21:10: INFO  Found 8 logic processors.
    Mar 30 23:21:10: INFO  CPU: Intel(R) Core(TM) i7 CPU         920  @ 2.67GHz
    Mar 30 23:21:10: INFO  Starting 8 workers.
    Mar 30 23:21:10: INFO  ---------------------------------------------------------
    Mar 30 23:21:17: INFO  Currently 76 percent complete. Processed 172 of 226 items.


In this example, the script detects that four CPU-cores are available. Hyper-threading is used as the core i7 920 supports it, so 8 workers are started. Don't miss the trailing space within the command section. 

#### Logging

One of the nice features of PPSS is logging. The output of every command on every item that is executed is logged into a single file. Below is an example of such a file:

    ===== PPSS Item Log File =====
    Host:		imac-2.local
    Item:		PPSS_LOCAL_TMPDIR/20080602.wav
    Start date:	Mar 03 00:10:32
    
    Encode of PPSS_LOCAL_TMPDIR/20080602.wav successful.
    
    Status:		Succes - item has been processed.
    Elapsed time (h:m:s): 0:4:48


As you can see, a lot of information is logged by PPSS about the processed item, including the time it took to process it. Of particular interest is the status line: it is based on the exit status of the executed command, so error detection is build-in.

This script is build with the goal to be very easy to use. It runs on Linux and Mac OS X. It should work on other Unix-like operating systems, such as Solaris, that support the Bash shell.

This script is (only) useful for jobs that can be easily broken down in separate tasks that can be executed in parallel. For example, encoding a bunch of wav-files to mp3-format, downloading a large number of files, resizing images, anything you can think of.

Please note that this script is _even useful on a single-core host_. Certain jobs, such as downloading files and processing these downloaded files can often be optimized by executing these processes in parallel. 

*_PPSS is always a work in progress and although it seems to work for me, it might not for you for reasons I'm currently not aware of. I would very much appreciate it if you try it out and create an issue if you find a bug. Thanks!_*

#### Distributed PPSS

From version 2.0 and onward, PPSS supports distributed computing. With this version, it is possible to run PPSS on multiple host that each process a part of the same queue of items. Nodes communicate with each other through a single SSH server. 

This script has already been used to convert 400 GB of WAV files to MP3 with 4 hosts, a Core i7 running Ubuntu, two Macs based on 1.8 and 2 ghz Core Duos running Leopard, and an 2,2 Ghz AMD system running Debian. 

The remarkable thing is that the Core 7i @ 3,6 Ghz processed 380 files, while the other three systems _combined_ only processed 199. Keep in mind that the Core 7i has only 4 physical cores...

http://chart.apis.google.com/chart?cht=p3&chd=t:66,11,11,12&chs=350x150&chl=Core%20i7%20|AMD|iMac|Mac%20Mini&noncense=test.png

It is difficult to give an impression how PPSS works in distributed mode, however maybe the status screen can give you an idea.


    mrt 29 22:18:27: INFO  =========================================================
    mrt 29 22:18:27: INFO                         |P|P|S|S|                         
    mrt 29 22:18:27: INFO  Distributed Parallel Processing Shell Script version 2.17
    mrt 29 22:18:27: INFO  =========================================================
    mrt 29 22:18:27: INFO  Hostname:	MacBoek.local
    mrt 29 22:18:27: INFO  ---------------------------------------------------------
    mrt 29 22:18:28: INFO  Status:		100 percent complete.
    mrt 29 22:18:28: INFO  Nodes:	        7
    mrt 29 22:18:28: INFO  ---------------------------------------------------------
    mrt 29 22:18:28: INFO  IP-address       Hostname            Processed     Status
    mrt 29 22:18:28: INFO  ---------------------------------------------------------
    mrt 29 22:18:28: INFO  192.168.0.4      Corei7                    155   FINISHED
    mrt 29 22:18:29: INFO  192.168.0.2      MINI.local                 34   FINISHED
    mrt 29 22:18:29: INFO  192.168.0.5      server                     29   FINISHED
    mrt 29 22:18:30: INFO  192.168.0.63     host3                       6   FINISHED
    mrt 29 22:18:31: INFO  192.168.0.64     host4                       6   FINISHED
    mrt 29 22:18:31: INFO  192.168.0.20     imac-2.local               34   FINISHED
    mrt 29 22:18:32: INFO  192.168.0.1      router                      7   FINISHED
    mrt 29 22:18:32: INFO  ---------------------------------------------------------
    mrt 29 22:18:32: INFO  Total processed:                           271

