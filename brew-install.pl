#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

my ($dry_run, $yes, $formulae_only, $casks_only, $missing_only, $prefix);
GetOptions(
    'dry-run'      => \$dry_run,
    'yes'          => \$yes,
    'formulae'     => \$formulae_only,
    'casks'        => \$casks_only,
    'missing-only' => \$missing_only,
    'arm|apple-silicon|m' => sub { $prefix = '/opt/homebrew' },
    'intel|x86|i'         => sub { $prefix = '/usr/local' },
    'prefix=s'            => \$prefix,
) or die "Usage: $0 [--arm|--intel] [--dry-run] --yes [--formulae|--casks] [--missing-only] <report-file>\n";

my $report = $ARGV[0] or die "Usage: $0 [--arm|--intel] --yes <report-file>\n";
open(my $fh, '<', $report) or die "Cannot read $report: $!\n";

# --- Resolve which brew binary to use ---
my $brew;
if ($prefix) {
    $brew = "$prefix/bin/brew";
    die "No brew binary found at $brew — wrong prefix?\n" unless -x $brew;
} else {
    my ($detected) = grep { -x "$_/bin/brew" } qw(/opt/homebrew /usr/local);
    die "Could not find brew — pass --arm, --intel, or --prefix DIR\n"
        unless $detected;
    $brew = "$detected/bin/brew";
    $prefix = $detected;
}

# --- Parse the report ---
my ($section, @formulae, @casks);
while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ /^\s*$/ or $line =~ /^#/;        # skip blanks/comments
    if    ($line =~ /^==\s*Formulae/) { $section = 'formulae'; next }
    elsif ($line =~ /^==\s*Casks/)    { $section = 'casks';    next }
    elsif ($line =~ /^==/)            { $section = undef;      next }

    my ($pkg) = $line =~ /^(\S+)/ or next;             # first token = name
    next unless $pkg =~ /^[A-Za-z0-9._+-]+$/a;         # sanity-check names

    if    ($section eq 'formulae') { push @formulae, $pkg }
    elsif ($section eq 'casks')    { push @casks,    $pkg }
}
close($fh);

die "No packages found in $report — is it the right file?\n"
    unless @formulae or @casks;

# --- Ask brew what's installed (once per type, not per package) ---
sub brew_installed {
    my ($type) = @_;          # 'formula' or 'cask'
    my @list;
    my $pid = open(my $ph, '-|', $brew, 'list', "--$type", '-1') or do {
        warn "Could not run '$brew list --$type': $!\n";
        return ();
    };
    while (my $line = <$ph>) {
        chomp $line;
        push @list, $line if $line =~ /^[A-Za-z0-9._+-]+$/a;
    }
    close($ph);
    return @list;
}

printf "Found %d formulae and %d casks in %s\n",
    scalar(@formulae), scalar(@casks), $report;
printf "Using brew: %s (prefix: %s)\n\n", $brew, $prefix;

my %installed;
if ($missing_only) {
    print "Checking installed packages via brew...\n";
    $installed{formula}{$_} = 1 for brew_installed('formula');
    $installed{cask}{$_}    = 1 for brew_installed('cask');
    printf "Brew reports %d formulae and %d casks installed\n\n",
        scalar(keys %{$installed{formula}}), scalar(keys %{$installed{cask}});
}

my $go   = ($yes && !$dry_run) ? 1 : 0;
my $mode = $go ? 'INSTALLING' : 'DRY RUN';

unless ($go) {
    print "*** DRY RUN — nothing will be installed. Pass --yes to execute. ***\n\n";
}

sub install {
    my ($type, $pkg) = @_;

    if ($missing_only && $installed{$type}{$pkg}) {
        printf "[skip]    %s: %s (brew reports it installed)\n", $type, $pkg;
        return 0;
    }
    printf "[%s] %s: %s\n", $mode, $type, $pkg;
    system($brew, 'install', "--$type", $pkg) if $go;
    return 1;
}

my $installed = 0;
unless ($casks_only) {
    for my $pkg (@formulae) { $installed += install('formula', $pkg) }
}
unless ($formulae_only) {
    for my $pkg (@casks)    { $installed += install('cask',    $pkg) }
}

my $summary = $go ? "$installed packages installed" : 'dry run only';
print "\nDone. ($summary)\n";
