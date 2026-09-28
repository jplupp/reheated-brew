#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

my ($dry_run, $yes, $prefix) = (0, 0, 0);
GetOptions(
    'dry-run'  => \$dry_run,
    'yes'      => \$yes,
    'arm'      => sub { $prefix = '/opt/homebrew' },
    'intel'    => sub { $prefix = '/usr/local' },
    'prefix=s' => \$prefix,
) or die "Usage: $0 [--arm|--intel] [--dry-run] --yes <report-file | pkg1 pkg2 ...>\n";

$prefix ||= (grep { -d "$_/Cellar" } qw(/opt/homebrew /usr/local))[0]
    or die "No Homebrew found — pass --arm, --intel, or --prefix DIR\n";

# --- Collect targets: report file and/or package names ---
my @pkgs;
for my $arg (@ARGV) {
    if (-f $arg) {
        # It's a file: parse it like brew-remove.pl does
        open(my $fh, '<', $arg) or die "Cannot read $arg: $!\n";
        my $section;
        while (my $line = <$fh>) {
            chomp $line;
            next if $line =~ /^\s*$/ or $line =~ /^#/;     # skip blanks/comments
            if    ($line =~ /^==\s*Formulae/) { $section = 'formulae'; next }
            elsif ($line =~ /^==\s*Casks/)    { $section = 'casks';    next }
            elsif ($line =~ /^==/)            { $section = undef;      next }

            my ($pkg) = $line =~ /^(\S+)/ or next;
            next unless $pkg =~ /^[A-Za-z0-9._+-]+$/a;      # sanitize names

            # Only take formulae — casks can't be removed without brew
            push @pkgs, $pkg if defined($section) && $section eq 'formulae';
        }
        close($fh);
        print "Parsed formulae from report: $arg\n";
    } else {
        # Treat as a package name
        die "'$arg' is neither a readable file nor looks like a package name\n"
            unless $arg =~ /^[A-Za-z0-9._+-]+$/a;
        push @pkgs, $arg;
    }
}

die "No packages to remove — pass a report file or package names\n" unless @pkgs;

my $go   = ($yes && !$dry_run) ? 1 : 0;
my $mode = $go ? 'REMOVING' : 'DRY RUN';

# Shared trees where Homebrew symlinks keg files into
my @link_dirs = qw(bin sbin lib include share etc libexec opt);

sub run {
    my ($desc, @cmd) = @_;
    print "  $desc\n";
    system(@cmd) if $go;
}

for my $pkg (@pkgs) {
    my $kegdir = "$prefix/Cellar/$pkg";
    unless (-d $kegdir) {
        print "[$mode] $pkg: not installed (skipping)\n";
        next;
    }
    print "[$mode] formula: $pkg\n";

    # 1. Remove symlinks pointing into this keg
    for my $sub (@link_dirs) {
        my $dir = "$prefix/$sub";
        next unless -d $dir;
        opendir(my $dh, $dir) or next;
        while (my $e = readdir($dh)) {
            my $path = "$dir/$e";
            next unless -l $path;                       # symlinks only
            my $target = readlink($path) // '';
            # Match both absolute and relative (../Cellar/...) targets
            if ($target =~ m{(^|/)Cellar/\Q$pkg\E(/|$)}) {
                run("unlink $path", '/bin/rm', '-f', $path);
            }
        }
        closedir($dh);
    }

    # 2. Remove the keg, the opt link, and metadata dir
    run("rm -rf $kegdir",               '/bin/rm', '-rf', $kegdir);
    run("rm -f $prefix/opt/$pkg",       '/bin/rm', '-f',  "$prefix/opt/$pkg");
    run("rm -rf $prefix/Cellar/.$pkg",  '/bin/rm', '-rf', "$prefix/Cellar/.$pkg");

    print "\n";
}

my $summary = $go ? 'packages removed' : 'dry run only';
print "Done. ($summary)\n";
