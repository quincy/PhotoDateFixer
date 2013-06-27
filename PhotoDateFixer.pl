#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
use File::Basename;
use File::Copy;

use lib q{C:/lib};
use Image::ExifTool ':Public';
use Getopt::Long qw{HelpMessage};
use Log::Message::Simple qw{:STD :CARP};
use Pod::Usage;


#-------------------------------------------------------------------------------
# CONSTANTS
#-------------------------------------------------------------------------------
my $EMPTY_STR = q{};
my $re_image_suffixes = qr{\.(?:jpg|jpeg)$}xmsi;
my ($g_sec,$g_min,$g_hour,$g_mday,$g_mon,$g_year,$g_wday,$g_yday,$g_isdst) = localtime(time);
my $YEAR = $g_year + 1900;

#-------------------------------------------------------------------------------
# GLOBALS
#-------------------------------------------------------------------------------
my $unchanged       = 0;
my $exif_updated    = 0;


#-------------------------------------------------------------------------------
# Process command line
#-------------------------------------------------------------------------------
my $opt = process_command_line();


#-------------------------------------------------------------------------------
# Start recursive search for images ending in .jpg
#-------------------------------------------------------------------------------
my @dirs  = ();
my @files = ();
push @dirs, $start_dir;

while (@dirs)
{
    my $dir = shift @dirs;
    opendir my $DIR, $dir or die "Unable to open $dir/ for reading.  $!\n";

    ENTRY:
    while (my $entry = readdir $DIR)
    {
        next ENTRY  if $entry eq '.' || $entry eq '..';

        my $path = "$dir/$entry";

        if (-d $path && $opt_recurse)
        {
            _debug("Adding $path to dirs.\n");
            push @dirs, $path;
        }
        elsif ($entry =~ m{$re_image_suffixes}xmsi
            && $entry =~ m{\d\d-\d\d-\d\d_\d\d\d\d}xms)
        {
            _debug("Adding $path to files.\n");
            push @files, $path;
        }
        else
        {
            _debug("Ignoring $path\n");
        }
    }

    closedir $DIR;
}

print "Found " . scalar(@files) . " images.\n";


#-------------------------------------------------------------------------------
# Now, examine the EXIF data for each file to see if the date tag is there.
#-------------------------------------------------------------------------------
foreach my $file (@files)
{
    my ($file_name, $file_dir, $suffix)     = fileparse($file);
    my ($file_date, $file_time)             = split /_/, $file_name;
    my ($file_month, $file_day, $file_year) = split /-/, $file_date;

    $file_date = format_date($file_year, $file_month, $file_day);

    my $info = ImageInfo($file);

    print win_path($file) . "\n";

    # DateTimeOriginal exists -- check if it matches the file name.
    if (exists $info->{DateTimeOriginal})
    {
        my ($exif_date, $exif_time) = split /\s+/, $info->{DateTimeOriginal};
        my ($exif_year, $exif_month, $exif_day) = split /:/, $exif_date;

        $exif_date = format_date($exif_year, $exif_month, $exif_day);

        if ($file_date eq $exif_date)
        {
            print "\tDateTimeOriginal : $info->{DateTimeOriginal}\n";
            print "\tThe date in the file name is equal to the date in the exif data.\n";
            ++$unchanged;
        }
        else
        {
            update_date_tag($info, $file, $file_year, $file_month, $file_day, $file_time);
        }
    }
    # DateTimeOriginal does not exist -- it will be set to the value of the file
    # name.
    else
    {
        print "\tDateTimeOriginal tag was not found.\n";

        update_date_tag($info, $file, $file_year, $file_month, $file_day, $file_time);
    }
}

print "\n";
printf "Files with EXIF data updated: %5d\n", $exif_updated;
printf "Files unchanged             : %5d\n", $unchanged;

exit 0;


#-------------------------------------------------------------------------------
# SUBROUTINES
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Sets the DateTimeOriginal EXIF tag to be equal to the date in the file name.
#-------------------------------------------------------------------------------
sub update_date_tag
{
    my ($info, $file, $year, $month, $day, $time) = @_;

    my $exif_date = format_exif_date($year, $month, $day);
    my $exif_time = substr($time, 0, 2) 
                  . ':' 
                  . substr($time, 2, 2) 
                  . ':00';

    print "\tDateTimeOriginal tag will be updated to [$exif_date $exif_time].\n";
    print "\tContinue? [y/n] ";

    if ($opt_dry_run)
    {
        print "y\n";
        ++$exif_updated;
    }
    else
    {
        my $answer = 'n';

        if ($opt_interactive)
        {
            $answer = <STDIN>;
            $answer = lc $answer;
            chomp $answer;
        }
        else
        {
            print "y\n";
            $answer = 'y';
        }

        if ($answer eq 'y')
        {
            my $exifTool = new Image::ExifTool;
            my ($success, $error) = $exifTool->SetNewValue(DateTimeOriginal => "$exif_date $exif_time");

            if ($success)
            {
                if (!$exifTool->WriteInfo($file))
                {
                    die "Error writing file!  " . $exifTool->GetValue('Error') . "\n";
                }
                else
                {
                    ++$exif_updated;
                    print "\tData has been written.\n";
                }
            }
            else
            {
                die "Error setting tag value!  $error\n";
            }
        }
        else
        {
            print "\tFile will not be modified.\n";
            ++$unchanged;
        }
    }
}


#-------------------------------------------------------------------------------
# Returns a date string in the format YYYY-MM-DD.
#-------------------------------------------------------------------------------
sub format_date
{
    my ($year, $month, $date) = @_;

    if ($year =~ m/^\d{2}$/xms)
    {
        $year += ($year+2000 <= $YEAR) ? 2000 : 1900;
    }

    my $new_date = qq{$year-$month-$date};

    return $new_date;
}


#-------------------------------------------------------------------------------
# Returns a date string in the format YYYY:MM:DD.
#-------------------------------------------------------------------------------
sub format_exif_date
{
    my ($year, $month, $date) = @_;

    if ($year =~ m/^\d{2}$/xms)
    {
        $year += ($year+2000 <= $YEAR) ? 2000 : 1900;
    }

    my $new_date = qq{$year:$month:$date};

    return $new_date;
}


#-------------------------------------------------------------------------------
# Prints debug messages.
#-------------------------------------------------------------------------------
sub _debug
{
    if ($opt->{debug})
    {
        print "DEBUG :: $_[0]";
    }
}


#-------------------------------------------------------------------------------
# Parse the command line and return a hash ref of the configuration options.
#-------------------------------------------------------------------------------
sub process_command_line
{
    my %options = (
        'help'        => 0,
        'man'         => 0,
        'usage'       => 0,
        'recurse'     => 1,
        'dry-run'     => 0,
        'interactive' => 0,
        'debug'       => 0,
        'verbose'     => 1,
        'directory'   => getcwd(),
    );

    GetOptions(
        'help'        => \$options{help},
        'man'         => \$options{man},
        'usage'       => \$options{usage},
        'debug!'      => \$options{debug},
        'verbose!'    => \$options{verbose},
        'recurse'     => \$options{recurse},
        'dry-run'     => \$options{'dry-run'},
        'interactive' => \$options{interactive},
        'directory=s' => \$options{directory},
    );

    pod2usage(-exitstatus => 0, -verbose => 0)  if $options{usage};
    pod2usage(-exitstatus => 0, -verbose => 1)  if $options{help};
    pod2usage(-exitstatus => 0, -verbose => 2)  if $options{man};

    if ($options{help} || $options{man} || $options{usage})
    {
        exit 0;
    }

    if (! -e $options{directory})
    {
        print "The specified start directory [$options{directory}] does not exist!\n";
        exit 1;
    }
    if (! -d $options{directory})
    {
        print "The specified start directory [$options{directory}] is not a directory!\n";
        exit 1;
    }
    _debug("Start dir is [$options{directory}].\n");

    return \%options;
}


__END__
=head1 PhotoDateFixer.pl

SCM: git@github.com:quincy/PhotoDateFixer.git

=head1 USAGE

$ PhotoDateFixer [options] {--directory=some_dir}

 Options:
    --help          Shows the full help screen.
    --man           Print the full man page documentation.
    --usage         Shows a brief usage message.
    --recurse       Search for photos recursively which is the default.  Use --norecurse to turn off.
    --dry-run       Show what would happen if the program were run.
    --interactive   Prompt for destructive actions.  Defaults to non-interactive mode.
    --debug         Print debugging messages.
    --verbose       Print verbose messages.
    --directory     The directory in which to begin the search.

=head1 OPTIONS

Options name can be abbreviated as long as they are unique.  You can combine options use the GNU short option style.

=over 4

=item B<--help>

Shows this screen.

=item B<--man>

Print the full man page documentation.

=item B<--usage>

Print a brief usage message.

=item B<--recurse>

Recursively search for images.  This is the default.  Turn off with --norecurse.

=item B<--dry-run>

Only show what would have happened.  Don't actually do anything destructive.

=item B<--interactive>

The program will prompt before any destructuve actions.  Defaults to non-interactive.

=item B<--debug>

Turn on debugging messages.

=item B<--verbose>

Turn on verbose messages.

=item B<--directory>

Specifies the directory where the search should begin.

=back

=head1 DESCRIPTION

Searches recursively for images that are missing EXIF date tags or that have
file names that look like a date but with EXIF data that doesn't match that.

The images that are identified can then have their EXIF data updated to the
correct values.

=head1 AUTHOR

Quincy Bowers B<qbowers@clearwateranalytics.com>

=cut

