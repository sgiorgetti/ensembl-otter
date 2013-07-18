
package Bio::Otter::Error;

use strict;
use warnings;

use Tk::ErrorDialog;

# grab a reference to Tk::ErrorDialog's Tk::Error()
my $tk_error_dialog;
BEGIN {
    $tk_error_dialog = \&Tk::Error;
}

# redefine Tk::Error() 
{
    no warnings qw( redefine ); ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    sub Tk::Error {
        my ($w, $error, @messages) = @_;
        # nb. @messages are a stacktrace, truncated by Tk where we
        # emerged from innermost event handler

        my $message = $error =~ /web server/
            ? 'There seems to be a problem with the web server, please try again later.'
            : "Unidentified problem: $error\n\nI suggest you raise a helpdesk ticket!"
            ;

        print STDERR "Tk::Error: $error", map { qq( $_\n) } @messages; # dump to the log
        $tk_error_dialog->($w, $message, @messages); # pop up the dialog

        # show that we have left the nested event loop
        print STDERR "(back from Tk::Error)\n";

        return;
    }
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

