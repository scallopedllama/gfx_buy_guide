#!/bin/bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This script is used to compare the prices and passmark benchmarks of graphic cards for sale on kakaku.com in Japan.
# The script could easily be modified to work with newegg for example but would require some modifications by somebody who knows how to work bash.
# I've added some notes throughout to help you modify the script to your needs.
# (c) 2011 Joe Balough

# See if help was requested
if [ "$1" == "-h" -o "$1" == "--h" -o "$1" == "--help" ]
then
  echo "Usage: $0 [number of kakaku pages to parse]";
  echo "    $0 is a shell script that uses sed to parse the html pages returned by frostytech.com"
  echo "    and kakaku.com to build a MySQL database that contains all that information."
  echo "    After all that, it queries the database to join the two sources of information to make selecting"
  echo "    a cpu cooler easier."
  echo "    The query outputs to a file called cooler_data.tsv in the current working directory."
  echo "    This file is a tab-separated-value file that is easily imported into any spreadsheet program."
  echo ""
  echo "    Note that the input is not checked for validity."
  echo "    You must also have a mysql database configured called 'guide' that you have full privilages on."
  exit 1
fi

# Print some info
echo "Going to retrieve HTML data I need."
echo -n "Frostytech.com cooler noise rankings: "

# Get the relevant pages with wget

# If the script fails to get this file or it fails to get an adequate number of entries for noise,
# The url wget retrieves here may need to be updated. Just go to frostytech.com and look at one of
# the coolers in the top 5 for your cpu and put the url for the page listing its noise raking here.
wget -q -O noise.n.html "http://www.frostytech.com/articleview.cfm?articleid=2521&page=3"
if [ -a "noise.html" ]
then
  echo "ok."
else
  echo "failed."
  echo "    There was a problem getting the noise rankings from frostytech"
  echo "    Check the url in the script and try again."
  exit 1
fi


echo -n "Frostytech.com cooler temperature rankings: "

# Get the relevant pages with wget

# If the script fails to get this file or it fails to get an adequate number of entries for noise,
# The url wget retrieves here may need to be updated. Just go to frostytech.com and look at one of
# the coolers in the top 5 for your cpu and put the url for the page listing its noise raking here.
wget -q -O temp.n.html "http://www.frostytech.com/articleview.cfm?articleid=2521&page=4"
if [ -a "temp.html" ]
then
  echo "ok."
else
  echo "failed."
  echo "    There was a problem getting the temperature rankings from frostytech"
  echo "    Check the url in the script and try again."
  exit 1
fi

echo "Getting kakaku.com page listings."

# Loop through getting all the kakaku page listings
for (( i=1; i<=$1; i++ ))
do
  # All the pages of the kakaku listings       \/ Page number, ex: 001, 002, etc
  #    http://kakaku.com/pc/cpu-cooler/ma_0/e20NN/s4=1/
  echo -n "  Page $i: "

  # This formats the current page counter to a string with 0s padding the front so that it is 2 characters long.
  # If the number of pages in your results go into the hundreds or thousands, you will need to modify the amount
  # padding this printf uses.
  j=$(printf "%02d" "$i")

  wget -q -O coolers$j.sj.html http://kakaku.com/pc/cpu-cooler/ma_0/e20$j/s4=1/

  # Make sure it's there
  if [ -a "coolers$j.sj.html" ]
  then
    echo "ok."
  else
    echo "failed."
    echo "    There was a problem getting the kakaku.com page listings."
    echo "    Check the url in the script and try again."
    exit 1
  fi

  # Kakaku.com uses the Shift_JIS encoding for all their pages. That needs to be converted to UTF-8
  # Or sed WILL fail to match Japanese characters with the . wildcard.
  # If you're working on a US site, you can remove these two lines. If it's some other international site,
  # you will probably have to change the from encoding after the -f tag.
  iconv -f SHIFT_JIS -t UTF-8 coolers$j.sj.html > coolers$j.html
  rm coolers$j.sj.html
done

# Remove the newlines from the frostytech files it got.. it's not a uniform looking page at all
tr -d '\n\r' < noise.n.html > noise.html
tr -d '\n\r' < temp.n.html > temp.html

# This will use sed to parse the relevant benchmark data out of the html of the noise.html file.
# That last 'g' is needed to ensure it does all replacements. The last 'p' combines with the -n option to ONLY print the lines that have been changed ONCE.
# Example line: <tr bgcolor="#d1dfe9">    <td>Spire</td>    <td>Thermax Eclipse</td>    <td></td>    <td>51.3 dB</td>    <td>Intel/AMD</td></tr>
# 1: Mfg    2: Model    3: Fan Speed    4: Noise    5:CPU
sed "s:</[tT][rR]>:</TR>\n:g" noise.html | sed -n "s:^.*<TR.*> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *</TR>.*$:\1\t\2\t\3\t\4:gp" > noise.tsv
# Example line: <tr bgcolor="#d1dfe9">    <td>Spire</td>    <td>Thermax Eclipse II (2 fans)</td>    <td></td>    <td>10.2</td>    <td>56.9</td></tr>
# 1: Mfg    2: Model   3: Fan Speed    4: 125W Test (degrees C)    5: Noise Level (dB)
sed "s:</[tT][rR]>:</TR>\n:g" temp.html | sed -n "s:^.*<TR.*> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *<TD> *\(.*\)</TD> *</TR>.*$:\1\t\2\t\3\t\4\t\5:gp" > temp.tsv

# Make sure there's some data in those files
noise_entries=`wc -l noise.tsv | awk '{print($1)}'`
if [ $noise_entries -lt 50 ]
then
  echo "Warning: The processed noise file gave fewer than 50 entries for the database."
  echo "         This may be because frostytech changed their site layout and the sed regex doesn't work anymore."
  echo "         Got $noise_entries entries. Continuing anyway."
fi
temp_entries=`wc -l temp.tsv | awk '{print($1)}'`
if [ $temp_entries -lt 50 ]
then
  echo "Warning: The processed temp file gave fewer than 50 entries for the database."
  echo "         This may be because frostytech changed their site layout and the sed regex doesn't work anymore."
  echo "         Got $temp_entries entries. Continuing anyway."
fi

exit 0

# This will use sed to parse the relevant data out of each of the html files for the kakaku listings.
# If you've never used sed before, it's probably a good idea to go look at a tutorial but here is the jist of what we're doing.
# Get an example line that contains ONE listing from the results page.
# Kakaku.com example line: "...<td class="item">INNOVISION<p><a href="http://kakaku.com/item/K0000166014/"><strong>Inno3D Geforce 9400GT [PCIExp 1GB]</strong></a></p></td><td class="td-price select"><a href="http://kakaku.com/item/K0000166014/">&#165;5,980</a><br><span>PC-IDEA</span></td><td>1店舗</td><td>382位</td><td>530位</td><td>-<br><a href="http://review.kakaku.com/review/K0000166014/">(0件)</a></td><td><a href="http://bbs.kakaku.com/bbs/K0000166014/">0件</a></td><td>-</td><td>10/11/10</td><td>PCIExp 16X&nbsp;</td><td>NVIDIA<br>GeForce 9400 GT&nbsp;</td><td>GDDR2<br>1024MB&nbsp;</td><td class="end">D-SUBx1<br>DVIx1&nbsp;</td></tr>"
# The general sed command is 'sed -n "s:[MATCH]:[REPLACE]:pg" [INPUT FILE] > [OUTPUT FILE]
# This command will only print a line if it has a match (because of the -n option and the p option) and will check every line in the file (because of the g option).
# [MATCH] Is a generalized string that you're looking for. ^ matches the start of the line, $ matches the end. Replace text with .*, numbers with [0-9]*, and wrap the information you want with \( and /). Escape all you're "s.
# [REPLACE] is the string you want to replace all that was match with. It'll be like \1\t\2\t\3\t\4. Each \# refers to the #th block of text you wrapped in \( and \). the \t is a tab. Space your fields out with \t so MySQL will be happy.
# 1: manufacturer, 2: model, 3: price, 4: price pt 2, 5: Chip, 6: ram type, 7: ram amount, 8: outputs
for (( i=1; i<=$1; i++ ))
do
  j=$(printf "%02d" "$i")
  # Append to the tsv file
  sed -n "s:^.*<td class=\"item\">\(.*\)<p><a href=.*><strong>\(.*\)</strong></a></p></td><td class=\"td-price select\"><a href=.*>&#165;\([0-9]*\),*\([0-9]*\)</a><br><span>.*</span></td><td>.*</td><td>.*</td><td>.*</td><td>.*<br><a href=.*>.*</a></td><td><a href=.*>.*</a></td><td>.*</td><td>.*</td><td>.*</td><td>.*<br>\(.*\)&nbsp;</td><td>\(.*\)<br>\(.*\)&nbsp;</td><td class=\"end\">\(.*\)&nbsp;</td></tr>:\1 \2\t\3\4\t\5\t\6\t\7\t\8:gp" cards$j.html >> cards.br.tsv
done

# Clean up the kakaku listing a little bit
# The output listings always have <br>s in them. Let's get rid of them really quick
sed "s:<br>: :g" cards.br.tsv > cards.n.tsv
# These two are probably not needed, but just in case.
sed "s:Geforce:GeForce:g" cards.n.tsv > cards.r.tsv
sed "s:RADEON:Radeon:g" cards.r.tsv > cards.tsv
rm cards.*.tsv

#make sure it has a reasonable number of entries
card_entries=`wc -l cards.tsv | awk '{print($1)}'`
if [ $card_entries -lt $(($1-1)) ]
then
  echo "Warning: The processed cards files gave fewer than 40 * ($1 pages - 1) entries."
  echo "         This may be because kakaku.com changed their site layout and the sed regex doesn't work anymore."
  echo "         Got $card_entries entries. Continuing anyway."
fi

# Status report
echo "Got $benchmark_entries benchmarks and $card_entries kakaku.com listings."
echo ""

# Get the mySql password and username
read -p "Please enter MySQL Username: " username
stty -echo
read -p "Please enter MySQL Password: " password; echo
stty echo

# Now run the relevant commands.
echo ""
echo -n "Dropping old tables..."
mysql -u$username -p$password -e "USE gpu; DROP TABLE benchmarks; DROP TABLE cards;" > /dev/null 2>&1
echo "ok"
echo -n "Re-creating old table..."
# Look at MySQL cheat sheets to understand what the particualrs of the fields are. You may need to modify the table descriptions to match the data you got from your retailer.
mysql -u$username -p$password -e "USE gpu; CREATE TABLE benchmarks (rank INT(6), gpu VARCHAR(256), score INT (11)); CREATE TABLE cards (name VARCHAR(256), price INT(11), gpu VARCHAR(256), ram_type VARCHAR(26), ram VARCHAR(26), outputs VARCHAR(256));"
echo "ok"
echo -n "Adding data..."
# Shouldn't need to modify this at all
mysql -u$username -p$password -e "USE gpu; LOAD DATA LOCAL INFILE \"benchmarks.tsv\" INTO TABLE benchmarks; LOAD DATA LOCAL INFILE \"cards.tsv\" INTO TABLE cards;"
echo "ok"
echo -n "Running query..."
# The important bit on this query is that it joins the gpu fields. You can change what it selects but make sure you have the INNER JOIN intact.
mysql -u$username -p$password -e "USE gpu; SELECT c.name, c.gpu, c.price, b.rank, b.score, c.ram_type, c.ram, c.outputs FROM cards c INNER JOIN benchmarks b ON c.gpu=b.gpu ORDER BY b.rank, price ASC;" > card_data.tsv
echo "ok"

echo ""
echo "All done."
echo "The joined data has been dumped into the file called card_data.tsv."
echo "It's a tab-separated-value file that can easily be pasted into a spreadsheet to get a better look at the data."
echo "All intermediate files including the original html data has been deleted. The MySQL database tables remain."

# Clean everything up
rm benchmarks.html
rm benchmarks.tsv
rm cards??.html
rm cards.tsv

exit 0