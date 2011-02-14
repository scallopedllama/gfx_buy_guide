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
rm noise.n.html temp.n.html

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

# This will use sed to parse the relevant data out of each of the html files for the kakaku listings.
for (( i=1; i<=$1; i++ ))
do
  j=$(printf "%02d" "$i")
  # 1: Mfg    2: url    3: model    4: price
  #         ...<td class=\"item\"> MFG  <p><a href=\" URL  \"><strong> MODEL</strong></a></p></td><td class=\"td-price\"><a href=..>&#165;        PRICE     </a><br><span>..</span></td><td>..</td><td>..</td><td>..</td><td>..<br><a href=..>..</a></td><td><a href=..>..</a></td><td>..</td><td class=\"select\">..</td><td>..</td><td>..</td><td>..</td><td>..</td><td class=\"end\">..</td></tr>
  sed -n "s:^.*<td class=\"item\">\(.*\)<p><a href=\"\(.*\)\"><strong>\(.*\)</strong></a></p></td><td class=\"td-price\"><a href=.*>&#165;\([0-9]*,*[0-9]*\)</a><br><span>.*</span></td><td>.*</td><td>.*</td><td>.*</td><td>.*<br><a href=.*>.*</a></td><td><a href=.*>.*</a></td><td>.*</td><td class=\"select\">.*</td><td>.*</td><td>.*</td><td>.*</td><td>.*</td><td class=\"end\">.*</td></tr>:\1\t\3\t\4\t\2:gp" coolers$j.html >> coolers.tsv
done

#make sure it has a reasonable number of entries
kakaku_entries=`wc -l coolers.tsv | awk '{print($1)}'`
one_less_pages=$(($1-1))
if [ $kakaku_entries -lt $(($one_less_pages*40)) ]
then
  echo "Warning: The processed kakaku search files gave fewer than 40 * ($1 pages - 1) entries."
  echo "         This may be because kakaku.com changed their site layout and the sed regex doesn't work anymore."
  echo "         Got $kakaku_entries entries. Continuing anyway."
fi

# Status report
echo "Got $noise_entries noise rankings, $temp_entries temperature rankings, and $kakaku_entries kakaku.com listings."
echo ""

# Get the mySql password and username
read -p "Please enter MySQL Username: " username
stty -echo
read -p "Please enter MySQL Password: " password; echo
stty echo

# Now run the relevant commands.
echo ""
echo -n "Dropping old tables..."
mysql -u$username -p$password -e "USE guide;
  DROP TABLE cool_kakaku; DROP TABLE cool_noise; DROP TABLE cool_temp;" > /dev/null 2>&1
echo "ok"
echo -n "Re-creating old table..."
# kakaku.tsv: Mfg      model     price        url
# noise.tsv:  Mfg      Model     Fan Speed    Noise
# temp.tsv:   Mfg      Model     Fan Speed    125W Test (degrees C)        Noise Level (dB)
mysql -u$username -p$password -e "USE guide;
  CREATE TABLE cool_kakaku (manufacturer VARCHAR(256), model VARCHAR(256), price INT(11), url VARCHAR(256));
  CREATE TABLE cool_noise  (manufacturer VARCHAR(256), model VARCHAR(256), fan_speed VARCHAR(16), noise VARCHAR(128));
  CREATE TABLE cool_temp   (manufacturer VARCHAR(256), model VARCHAR(256), fan_speed VARCHAR(16), temp DOUBLE, noise DOUBLE);"
echo "ok"
echo -n "Adding data..."
mysql -u$username -p$password -e "USE guide;
  LOAD DATA LOCAL INFILE \"kakaku.tsv\" INTO TABLE cool_kakaku;
  LOAD DATA LOCAL INFILE \"noise.tsv\" INTO TABLE cool_noise;
  LOAD DATA LOCAL INFILE \"temp.tsv\" INTO TABLE cool_temp;"
echo "ok"
echo -n "Running query..."
mysql -u$username -p$password -e "USE guide;
  SELECT DISTINCT k.manufacturer, k.model, k.price, n.noise, t.temp, k.url
  FROM cool_kakaku k
  LEFT JOIN cool_noise n ON k.model=n.model
  LEFT JOIN cool_temp t ON k.model=t.model
  ORDER BY k.price ASC;" > cooler_data.n.tsv
echo "ok"

# mySQL wrapps the output with a \r which is useless to us so look for the string \r and replace it with nothing
# While at that, replace all the NULLs with empty strings.
sed 's:\r::g' cooler_data.n.tsv | sed 's:NULL::g' > cooler_data.tsv
rm cooler_data.n.tsv

echo ""
echo "All done."
echo "The joined data has been dumped into the file called cooler_data.tsv."
echo "It's a tab-separated-value file that can easily be pasted into a spreadsheet to get a better look at the data."
echo "All intermediate files including the original html data has been deleted. The MySQL database tables remain."

# Clean everything up
rm temp.html
rm temp.tsv
rm coolers??.html
rm coolers.tsv
rm noise.html
rm noise.tsv

exit 0