#!/usr/bin/env perl

use Test::Otter;                # find t/lib

use Test::Bio::Otter::Lace::CloneSequence;
use Test::Bio::Vega::ContigInfo;

BEGIN {
    OtterTest::Class->run_all(1);
}

# OtterTest::Class::INIT does this now:
# Test::Class->runtests;

1;

# Local Variables:
# mode: perl
# End:

# EOF
