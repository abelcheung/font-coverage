#!/usr/bin/perl -w

################################################################################
# Copyright (c) 2014, Abel Cheung
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
use Font::TTF;
use Font::TTF::Font;
use Font::TTF::Ttc;
use Getopt::Std;

my ($csv, $req_uni_ver, @f, $c);
my %char_count = ();
my $default_uni_ver = '6.3.0';

my %opts = ();
getopts ('hilsu:z', \%opts);

sub usage {
	print <<_EOT_;

Usage: $0 [option...] FONT_FILE...

Prints a summary of Unicode blocks covered by Truetype/Opentype font with
glyph count. For Truetype Collections, all TTFs within are counted separately.

Numbers appearing in output represents, in order:
 * Total number of code points assigned for specific Unicode range
 * Number of glyphs found within the range AND assigned by unicode
 * Number of glyphs found within the range but NOT assigned by unicode

All code points in Control Chars, Surrogates and Private Use Areas are treated
as unassigned.

Options:
-h           Print this help
-i           Ignore code points that have no corresponding glyphs
-l           List supported Unicode versions on this system
-s           Generate CSV output format
-u VERSION   Use another Unicode version as reference (default 6.3.0)
               available versions are in include/ folder
-z           List Unicode blocks with no glyph in font (hidden by default)

_EOT_
	exit (1);
}

sub list_supported_uni_ver {
	print "Supported Unicode versions on this system:\n\n";
	foreach (<include/*>) {
		s#^include/##;
		print $_."\n" if ( -f "include/$_/FontCoverage.pm" );
	}
	exit (0);
}

usage if ( $opts{'h'} || (! @ARGV) );
list_supported_uni_ver if $opts{'l'};

$req_uni_ver = $opts{'u'} // $default_uni_ver;
if (! -d "include/$req_uni_ver") {
	print STDERR "No data for Unicode version '$req_uni_ver'\n";
	print STDERR "Use '$0 -l' to list supported versions\n";
	exit (3);
}

# Include data for appropriate unicode version
unshift @INC, "./include/$req_uni_ver";
require FontCoverage;

# strict warning suppresion
1?1:$FontCoverage::assign_map;

# http://blogs.msdn.com/b/jeuge/archive/2005/06/08/hakmem-bit-count.aspx 
sub bitsum {
	my $a = $_[0] - (($_[0] >> 1) & 033333333333) - (($_[0] >> 2) & 011111111111);
	return (($a + ($a >> 3)) & 030707070707) % 63;
}

sub populate_char_count {
	my ($char_count, @f) = @_;

	foreach my $ttf (@f) {

		my ($fontname, $ms_cmap, @font_mapping);

		$fontname = $ttf->{'name'}->read->find_name(4); # 4 = Full font name

		if (!$ttf->{'cmap'}) {
			print STDERR "Cmap table not found for '$fontname', abandon parsing\n";
			next;
		}
		if (defined $char_count->{$fontname}) {
			print STDERR "Font '$fontname' has already been scanned, skipping\n";
			next;
		}

		print STDERR "Start scanning " . $fontname ." ...";

		$opts{'i'} and $ttf->{'loca'}->read;
		$ms_cmap = $ttf->{'cmap'}->read->find_ms; # Microsoft unicode cmap table

		foreach (keys %{$ms_cmap->{'val'}}) {
			# check if glyph really exists with -i option
			$font_mapping[$_>>5] |= (1<<($_ & 0x1F)) if ((!$opts{'i'}) ||
				($ttf->{'loca'}->{'glyphs'}[$ms_cmap->{'val'}{$_}]));
		}

		foreach my $blockname (keys %{$FontCoverage::block_list}) {

			my $r1 = $FontCoverage::block_list->{$blockname}{'start'};
			my $r2 = $FontCoverage::block_list->{$blockname}{'end'};

			my @range_mask = (0xFFFFFFFF) x (($r2>>5) - ($r1>>5) + 1);
			$range_mask[0] &= ~((1<<($r1 & 0x1F)) - 1);
			$range_mask[$#range_mask] >>= (31-($r2 & 0x1F));

			$char_count->{$fontname}{$blockname}{'expected'} = 0;
			$char_count->{$fontname}{$blockname}{'unexpected'} = 0;

			# essentially count bits in (font_map & unicode_assign_map & range_mask)
			for my $i (($r1>>5) .. ($r2>>5)) {
				next if (!$font_mapping[$i]);
				my $bits = $font_mapping[$i] & $range_mask[$i-($r1>>5)];
				my $assign_map = $FontCoverage::assign_map->[$i];
				my $count = $char_count->{$fontname}{$blockname};

				if (!$assign_map) {
					$count->{'unexpected'} += bitsum($bits);
				} elsif ($assign_map == 0xFFFFFFFF) {
					$count->{'expected'}   += bitsum($bits);
				} else {
					$count->{'expected'}   += bitsum($bits & $assign_map);
					$count->{'unexpected'} += bitsum($bits & ~$assign_map);
				}
			}
		}
		print STDERR " Done.\n";

		# cause error for shared cmap in TTC
#		$ttf->release;
	}
}

foreach (@ARGV) {
	if ( ! -f ) {
		print STDERR "File '$_' not found, skipping\n";
		next;
	}
	eval {
		if (/\.ttc$/i) {
			if ( $c = Font::TTF::Ttc->open($_) ) {
				print STDERR "'$_' is a Truetype Collection, reading all embedded TTFs\n";
				push @f, @{$c->{'directs'}};
			}
		}
	} or do {
		if ( my $i = Font::TTF::Font->open($_) ) {
			push @f, ($i);
		} else {
		   	print STDERR "Failed to read font '$_', skipping\n";
		}
	};
}
if (!@f) {
	print STDERR "No valid font specified, quitting\n";
	exit (2);
}

populate_char_count (\%char_count, @f);

if ($opts{'s'}) {
	use Text::CSV;
	$csv = Text::CSV->new();
}

foreach my $fontname (keys %char_count) {
	print "\n=== " . $fontname . "\n\n";

	# CSV header
	if ($opts{'s'}) {
		$csv->combine(('Block Name', 'Start', 'End', 'Total codepoints', 'Assigned', 'Reserved'));
		print $csv->string()."\n";
	}

	my $blocks = $FontCoverage::block_list;
	my $count  = $char_count{$fontname};

	foreach (sort {$blocks->{$a}{'start'} <=> $blocks->{$b}{'start'}} keys %{$count}) {
		# Don't print unicode blocks for which the font has no glyph
		if ( !$opts{'z'} ) {
			next if ( (!$count->{$_}{'expected'}) &&
			          (!$count->{$_}{'unexpected'}) );
		}
		if ( $opts{'s'} ) {
			$csv->combine((
					$_,
					sprintf ("U+%04X", $blocks->{$_}{'start'}),
					sprintf ("U+%04X", $blocks->{$_}{'end'}),
					$blocks->{$_}{'assigned_total'},
					$count->{$_}{'expected'},
					$count->{$_}{'unexpected'}
				));
			print $csv->string()."\n";
		} else {
			printf "%s (U+%04X-U+%04X) => %d / %d / %d\n",
					$_,
					$blocks->{$_}{'start'},
					$blocks->{$_}{'end'},
					$blocks->{$_}{'assigned_total'},
					$count->{$_}{'expected'},
					$count->{$_}{'unexpected'};
		}
	}
}

print "\n";

exit 0;
