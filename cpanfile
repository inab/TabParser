requires 'perl', '5.008005';

# requires 'Some::Module', 'VERSION';
requires 'Carp';
requires 'IO::File';

on test => sub {
    requires 'Test::More', '0.96';
};