#!/usr/bin/perl
# Use this first to list your packages
use strict;
use warnings;
use Getopt::Long;

my $prefix;
GetOptions(
    'arm|apple-silicon|m' => sub { $prefix = '/opt/homebrew' },
    'intel|x86|i'         => sub { $prefix = '/usr/local' },
    'prefix=s'            => \$prefix,
) or die "Usage: $0 [--arm|--intel|--prefix DIR] [output-file]\n";

# Fallback: auto-detect if no flag given
unless ($prefix) {
    ($prefix) = grep { -d "$_/Cellar" } qw(/opt/homebrew /usr/local);
    die "No Homebrew Cellar found — pass --arm, --intel, or --prefix DIR\n"
        unless $prefix;
}

die "No Cellar found under $prefix — wrong prefix?\n"
    unless -d "$prefix/Cellar";

my $out_file = $ARGV[0] // 'homebrew-packages.txt';

open(my $fh, '>', $out_file) or die "Cannot write $out_file: $!\n";

print $fh "# Homebrew packages — generated ", scalar(localtime), "\n";
print $fh "# Prefix: $prefix\n\n";

my ($n_formulae, $n_casks) = (0, 0);

# --- Formulae (Cellar) ---
my $cellar = "$prefix/Cellar";
if (opendir(my $dh, $cellar)) {
    print $fh "== Formulae ==\n";
    for my $pkg (sort grep { !/^\./ } readdir($dh)) {
        my @versions;
        if (opendir(my $p, "$cellar/$pkg")) {
            @versions = grep { !/^\./ && -d "$cellar/$pkg/$_" } readdir($p);
            closedir $p;
        }
        my $ver = @versions ? join(', ', sort @versions) : '?';
        print $fh sprintf("%-30s %s\n", $pkg, $ver);
        $n_formulae++;
    }
    closedir $dh;
}

# --- Casks (Caskroom) ---
my $caskroom = "$prefix/Caskroom";
if (opendir(my $ch, $caskroom)) {
    print $fh "\n== Casks ==\n";
    for my $pkg (sort grep { !/^\./ } readdir($ch)) {
        print $fh "$pkg\n";
        $n_casks++;
    }
    closedir $ch;
}

close($fh);

print "Wrote $out_file: $n_formulae formulae, $n_casks casks (prefix: $prefix)\n";
