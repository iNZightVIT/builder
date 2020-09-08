#!/usr/local/bin/python3

import os
import platform
import datetime
import argparse

parser = argparse.ArgumentParser(description='Generate index.html files from a base directory')
parser.add_argument('-p', '--path', help='The starting point to run the script over')
args = parser.parse_args()

if (args.path):
  os.chdir(args.path)

def creation_date(path_to_file):
    """
    Try to get the date that a file was created, falling back to when it was
    last modified if that isn't possible.
    See http://stackoverflow.com/a/39501288/1709587 for explanation.
    """
    return '{0:%Y-%m-%d %H:%M:%S}'.format(datetime.datetime.fromtimestamp(os.path.getmtime(path_to_file)))

def convert_bytes(num):
    """
    this function will convert bytes to MB.... GB... etc
    """
    for x in ['bytes', 'KB', 'MB', 'GB', 'TB']:
        if num < 1024.0:
            return "%3.1f %s" % (num, x)
        num /= 1024.0


def file_size(file_path):
    """
    this function will return the file size
    """
    if os.path.isfile(file_path):
        file_info = os.stat(file_path)
        return convert_bytes(file_info.st_size)

for dirname, dirnames, filenames in os.walk('.'):
  html_str = """
      <!DOCTYPE html>
      <html>

      <head>
        <title>iNZight Package Repository</title>

        <link rel='stylesheet' type='text/css' href='/style.css'>
      </head>

      <body>
        <div id="container">
          <h1>iNZight Package Repository</h1>
    """
  html_str = html_str + "<h3>Index of " + dirname + "</h3>"
  html_str = html_str + """
          <table>
            <tr class="header">
              <th></th>
              <th>Name</th>
              <th>Last Modified</th>
              <th>Size</th>
            </tr>
  """

  if (dirname.count('\\') > 1) or (dirname.count('/') > 1):
    html_str = html_str + "<tr><td class=\"nopad\"><img src=\"/R/icons/updir.png\"></td><td><a href=\"../\">Parent Directory</a></td><td> - </td><td> - </td></tr>"

  for subdirname in sorted(dirnames):
    #print(os.path.join(dirname, subdirname))
    if not ((subdirname == "icons") or (subdirname == "templates") or (subdirname == "data") or (subdirname == "tracker")):
      editTime = creation_date(os.path.join(dirname, subdirname))
      html_str = html_str + "<tr><td class=\"nopad\"><img src=\"/icons/folder.png\"></td><td><a href=\"" + subdirname + "/\">" +subdirname + "/</a></td><td>" + str(editTime) + "</td><td> - </td></tr>"

  for filename in sorted(filenames):
    if not ((filename == "index.html") or (filename == "create_webpages.py") or (filename == "create_webpages.7z") or (filename == "style.css")):
      #print(os.path.join(dirname, filename))
      editTime = creation_date(os.path.join(dirname, filename))
      fileSize = file_size(os.path.join(dirname, filename))
      html_str = html_str + "<tr><td class=\"nopad\"><img src=\"/icons/file.png\"></td><td><a href=\"" + filename + "\">" + filename + "</a></td><td>" + str(editTime) + "</td><td>" + fileSize + "</td></tr>"
          
  html_str = html_str + """
          </table>
          <p class="footer">
          For technical support, please contact <a href="mailto:inzight_support@stat.auckland.ac.nz">inzight_support@stat.auckland.ac.nz</a>.
        </p>
        </div>
      </body>
      </html>
  """
  writePath = dirname + "/index.html"
  html_file = open(writePath,"w")
  html_file.write(html_str)
  html_file.close()
    # print path to all subdirectories first.
    #for subdirname in dirnames:
        #print(os.path.join(dirname, subdirname))

    # print path to all filenames.
    #for filename in filenames:
        #print(os.path.join(dirname, filename))
