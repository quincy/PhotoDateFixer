#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
use File::Basename;
use File::Copy;

use lib q{C:/lib};
use Image::ExifTool ':Public';

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
my $opt_debug       = 0;
my $opt_recurse     = 1;
my $opt_dry_run     = 0;
my $opt_interactive = 0;
my $start_dir       = $EMPTY_STR;
my $unchanged       = 0;
my $exif_updated    = 0;


# Parse command line arguments.
foreach my $arg (@ARGV)
{
    if ($arg eq '-debug')
    {
        $opt_debug = 1;
    }
    elsif ($arg eq '--no-recurse')
    {
        $opt_recurse = 0;
    }
    elsif ($arg =~ m{^--?h(?:elp)?}xms)
    {
        while (<DATA>)
        {
            print;
        }
        exit 0;
    }
    elsif ($arg eq '--interactive' || $arg eq '-i')
    {
        $opt_interactive = 1;
    }
    elsif ($arg eq '--dry-run')
    {
        $opt_dry_run = 1;
    }
    else
    {
        $start_dir = $arg;
        $start_dir =~ tr!\\!/!;
    }
}

$start_dir = getcwd()  if !$start_dir;

_debug("Start dir is " . win_path($start_dir) . ".\n");

if (! -e $start_dir)
{
    print "The specified start directory does not exist!\n";
    exit 1;
}
if (! -d $start_dir)
{
    print "The specified start directory is not a directory!\n";
    exit 1;
}

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
# Transforms Perl's internal Win32 paths into real Win32 paths.
#-------------------------------------------------------------------------------
sub win_path
{
    my $path = shift @_;
    $path    =~ tr!/!\\!;

    return $path;
}

#-------------------------------------------------------------------------------
# Prints debug messages.
#-------------------------------------------------------------------------------
sub _debug
{
    if ($opt_debug)
    {
        print "DEBUG :: $_[0]";
    }
}


__END__
PhotoDateFixer Help Screen

Searches recursively for images that are missing EXIF date tags or that have
file names that look like a date but with EXIF data that doesn't match that.

The images that are identified can then have their EXIF data updated to the 
correct values.

USAGE

$ PhotoDateFixer [-h] [-debug] [directory]

-h              Show this message.

-debug          Show debugging information.

--no-recurse    Don't search directories recursively.

--dry-run       Prints the results of what would happen if you answered yes to 
                all questions.  No changes to any file is actually made.

directory       You can specify the directory to start the search from.  If this 
                is not specified the current directory is assumed.

