#!/usr/bin/perl -w

################################################################################
# Copyright (c) 2014-19, Abel Cheung
# FontCoverage is licensed under BSD 2-clause license.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
################################################################################

use strict;
use version;
use 5.014; #s///r
use File::Temp qw( tempfile );
use File::Path qw( make_path );

if (!@ARGV || ($ARGV[0] eq "-h") || ($ARGV[0] eq "--help")) {
	print <<_EOT_;

Usage: $0 UNICODE_VERSION

It reads unicode UCD data from Unicode-mirror/<version> folder, and generate
private module for use with Font Coverage script.

For example, to generate Unicode 6.3.0 include file, mirror
http://www.unicode.org/Public/6.3.0 to ./Unicode-mirror/6.3.0
and invoke this script. Resulting file would be placed under
./include/6.3.0/

Some earlier Unicode versions might have Blocks.txt missing, which need to
be copied from nearest earlier version.

_EOT_
	exit (1);
}

my $uni_ver = $ARGV[0];
if (! -d 'Unicode-mirror/'.$uni_ver ) { die "No UCD data for Unicode version '$uni_ver' is found; please mirror from unicode.org\n"; }

my ($UO_unicodedatafile, $UO_blocksfile);
if (ver_compare ($uni_ver, "4.1") == 1) {
	$UO_unicodedatafile = "Unicode-mirror/$uni_ver/ucd/UnicodeData.txt";
	$UO_blocksfile = "Unicode-mirror/$uni_ver/ucd/Blocks.txt";
} else {
	($UO_unicodedatafile) = <Unicode-mirror/$uni_ver/UnicodeData*.txt>;
	($UO_blocksfile) = <Unicode-mirror/$uni_ver/Blocks*.txt>;
}

if ((!defined $UO_unicodedatafile) || (!-f $UO_unicodedatafile)) {
	die "UnicodeData*.txt not found\n";
}
if ((!defined $UO_blocksfile) || (!-f $UO_blocksfile)) {
	die "Blocks*.txt not found\n";
}

my $inc_folder = 'include/'. $uni_ver;
my $dest = $inc_folder . '/FontCoverage.pm';
die "File already generated for this Unicode version, quitting\n" if (-f $dest);

#
# Read Unicode Data
#
open (my $unidata, '<', $UO_unicodedatafile) or die ("UnicodeData text file can't be opened\n");

my @assign_map = ();
my $codepoint_count = 0;

my $in_range = 0;
my $first = undef;
my $last = undef;

while(<$unidata>) {
	my ($code, $desc, $dummy) = split ';';

	die "Corrupt UnicodeData.txt content\n" if ( (!defined $desc) || (!defined $dummy) );

	# Treat all surrogate, control char & PUA code points as unassigned
	next if ($desc =~ /^<(control|.*Private Use.*|.*Surrogate.*)>$/);

	$code = hex($code);

	# Only count BMP, SMP, SIP planes to save time & space
	# Other planes have no displayable glyph yet
	next if ($code >= 0x30000);

	if ($desc =~ /^<.*First>$/) {
		$first = $code;
		$in_range = 1;
		next;
	}
	if ($desc =~ /^<.*Last>$/) {
		die "Broken UnicodeData; range end without start\n" if (!$in_range);
		$last = $code;
		die "Broken UnicodeData; end < start\n" if ($first > $last);
		for ($first .. $last) {
			$assign_map[$_ >> 5] |= 1<<($_ & 0x1F);
			$codepoint_count++;
		}
		$first = $last = undef; $in_range = 0;
		next;
	}

	$assign_map[$code>>5] |= 1<<($code & 0x1F);
	$codepoint_count++;
}

close $unidata;

# see if bit is set in assign map
sub is_assigned_in_unicode {
	return defined $assign_map[$_[0]>>5] ? $assign_map[$_[0]>>5] & (1<<($_[0] & 0x1F)) : 0;
}

#
# Read unicode block list
#
open (my $uniblock, '<', $UO_blocksfile) or die ("Blocks text file can't be opened\n");

my @unicode_blocks;

while (<$uniblock>) {
	my ($start, $end, $desc);
	my $assigned_total = 0;

	# Format change in Blocks.txt since Unicode 3.1
	if ( (ver_compare ($uni_ver, "3.1") >= 0)
		&& /^([[:xdigit:]]+)\.\.([[:xdigit:]]+);\s*(.+)?\s*$/ ) {
		$start = hex($1); $end = hex($2); $desc = $3;
	} elsif ( (ver_compare ($uni_ver, "3.1") < 0)
		&& /^([[:xdigit:]]+);\s*([[:xdigit:]]+);\s*(.+)?\s*$/ ) {
		$start = hex($1); $end = hex($2); $desc = $3;
	}

	next if (!$desc);

	# A little deviation from official block lists
	# Separate C0/C1 control chars into their own ranges
	if ($desc =~ /^Basic Latin$/) {
		push @unicode_blocks, { 'start' => $start, 'end' => $start+0x1F,
			'desc' => 'C0 Control Character', 'assigned_total' => 0 };
		$start += 0x20;
	}
	if ($desc =~ /^Latin-1 Supplement$/) {
		push @unicode_blocks, { 'start' => $start, 'end' => $start+0x1F,
			'desc' => 'C1 Control Character', 'assigned_total' => 0 };
		$start += 0x20;
	}

	# Here comes the ugly part. Block names are not unique until
	# Unicode 3.2, but they are used as hash key here (for some laziness
	# reason). In order to mitigate problem, PUAs are renamed to post-3.2
	# versions, while one of the Specials blocks with only 0xFEFF code
	# point is dropped completely (fonts shouldn't have that glyph because
	# it's BOM!)
	if (ver_compare ($uni_ver, "3.2") < 0 ) {
		next if ($start == 0xFEFF);
		if ($start == 0xF0000) { $desc = 'Supplementary Private Use Area-A'; }
		if ($start == 0x100000) { $desc = 'Supplementary Private Use Area-B'; }
	}

	for ($start .. $end) {
		if (is_assigned_in_unicode($_)) { $assigned_total++; }
	}
	push @unicode_blocks, { 'start' => $start, 'end' => $end,
		'desc' => $desc, 'assigned_total' => $assigned_total };
}

close $uniblock;


#
# Start dumping file
#
my ($fh, $tempname) = tempfile( UNLINK => 0, SUFFIX => '.pm', DIR => '.' );
print $fh <<_EOT_;
package FontCoverage;

#
# This is a generated file used for FontCoverage script
#

_EOT_

# Dump assignment mapping
print $fh 'our $assign_map = [';
for (0 .. @assign_map) {
	($_ % 8) or print $fh "\n";
	($_ % 64) or printf $fh "### 0x%X\n", $_<<5;
	printf $fh "0x%-8X, ", ($assign_map[$_] // 0);
}
print $fh "\n];\n\n";

# Dump block list
print $fh "our \$block_list = {\n";
foreach (@unicode_blocks) {
	printf $fh "  '%s' =>\n    { 'start' => 0x%04X, 'end' => 0x%04X, 'assigned_total' => %d },\n",
		$_->{'desc'}, $_->{'start'}, $_->{'end'}, $_->{'assigned_total'};
}
print $fh "};\n1;\n";

close $fh;

make_path ($inc_folder, { mode => 0755 } );

unlink $dest;
rename $tempname, $dest;
chmod 0644, $dest;

print STDERR "File generation is successful.\n";

exit 0;

sub ver_compare {
	my $v1 = version->parse( shift =~ s/-Update$/-Update0/r =~ s/-Update/./r );
	my $v2 = version->parse( shift =~ s/-Update$/-Update0/r =~ s/-Update/./r );
	return $v1 cmp $v2;
}
