import fnmatch
import os
import re

src_path = "src"
make_path = "toolchain/makefile.mak"
fileformat = "sv"

verilog_filelist = []
filename_list = []
filenames_no_path = []
blacklist = ["defines.sv"]

# Fetch all filenames (with their path) recursively:
for root, dirnames, filenames in os.walk(src_path):
	for filename in fnmatch.filter(filenames, '*.'+fileformat):
		if(filename in blacklist):
			continue
		print filename
		verilog_filelist.append(os.path.join(root, filename).replace("\\", "/"))

# Read entire Makefile:
make_src = ""
with open(make_path, 'r') as content_file:
    make_src = content_file.read()

# Prepare buffer which contains the changes:
# Binaries/Object files:
make_src_new = "BINS = "
for i in range(len(verilog_filelist)):
	# Fetch and format filenames:
	filename = verilog_filelist[i][verilog_filelist[i].index('/')+1 : verilog_filelist[i].rindex('.')]
	filename_nopath = filename
	if('/' in filename_nopath):
		filename_nopath = filename[filename.rindex('/')+1:]
	# Push filenames into list:
	filename_list.append(filename)
	filenames_no_path.append(filename_nopath)

	# Write binary list for makefile:
	make_src_new += "$(BIN)/" + filename_nopath + ".o "
	if(i < len(verilog_filelist)-1):
		make_src_new += "\\\n\t"
	else:
		make_src_new += "\n\n"

# Rules:
command_template = "$(IVERI) -o $@ $(VERIFLAGS) $^"
for i in range(len(filename_list)):
	make_src_new += "$(BIN)/"+filenames_no_path[i]+".o: $(SRC)/"+filename_list[i]+"."+fileformat + "\n\t"+command_template+"\n\n"

# Append temination token:
make_src_new += "#__GENMAKE_END__"

# Make replacements:
make_src = re.sub(r"#__GENMAKE__(?:|\n|^|$|.)+#__GENMAKE_END__", "#__GENMAKE__\n"+make_src_new, make_src)

# Substitute makefile with the new one:
makefile = open(make_path, "wb")
makefile.write(make_src)
makefile.close()

print "Genmake: Makefile updated"