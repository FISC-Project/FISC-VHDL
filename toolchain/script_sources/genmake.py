import fnmatch
import os
import re

src_path = "src"
make_path = "toolchain/makefile.mak"
fileformat = "vhdl"

vhdl_filelist = []
filename_list = []
filenames_no_path = []
blacklist = ["defines.vhdl"]

# Fetch all filenames (with their path) recursively:
for root, dirnames, filenames in os.walk(src_path):
	for filename in fnmatch.filter(filenames, '*.'+fileformat):
		if(filename in blacklist):
			continue
		print filename
		vhdl_filelist.append(os.path.join(root, filename).replace("\\", "/"))

# Read entire Makefile:
make_src = ""
with open(make_path, 'r') as content_file:
    make_src = content_file.read()

# Prepare buffer which contains the changes:
# Binaries/Object files:
make_src_new = "BINS = "

if 0: # TODO: REMOVE THIS WHOLE IF LATER
	for i in range(len(vhdl_filelist)):
		# Fetch and format filenames:
		filename = vhdl_filelist[i][vhdl_filelist[i].index('/')+1 : vhdl_filelist[i].rindex('.')]
		filename_nopath = filename
		if('/' in filename_nopath):
			filename_nopath = filename[filename.rindex('/')+1:]
		# Push filenames into list:
		filename_list.append(filename)
		filenames_no_path.append(filename_nopath)

		# Write binary list for makefile:
		make_src_new += "$(BIN)/" + filename_nopath + ".o "
		if(i < len(vhdl_filelist)-1):
			make_src_new += "\\\n\t"
		else:
			make_src_new += "\n\n"

# Rules:
command_template = "\t$(GHDL) -a $(GHDLFLAGS) $^"

for i in range(len(filename_list)):
	make_src_new += "$(BIN)/"+filenames_no_path[i]+".o: $(SRC)/"+filename_list[i]+"."+fileformat + "\n\t@printf \"2."+str(i+1)+"- Analysing file '"+filename_list[i]+"': \"\n"+command_template+"\n\n"

# Append temination token:
make_src_new += "#__GENMAKE_END__"

# Make replacements:
make_src = re.sub(r"#__GENMAKE__(?:|\n|^|$|.)+#__GENMAKE_END__", "#__GENMAKE__\n"+make_src_new, make_src)

# Substitute makefile with the new one:
makefile = open(make_path, "wb")
makefile.write(make_src)
makefile.close()

print "Genmake: Makefile updated"