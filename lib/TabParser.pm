#!/usr/bin/perl

use strict;
use 5.008_005;
use utf8;
use warnings 'all';

use Carp;
use IO::File;	# For getline

package TabParser;

our $VERSION = '0.01';

=encoding utf-8

=head1 NAME

TabParser - A parser of tabulated or comma separated value files

=head1 SYNOPSIS

  use TabParser;

=head1 DESCRIPTION

TabParser is a library which eases parsing tabular files (or data
streams), using the least possible memory and calling callbacks defined
before parsing task.

=cut

use constant {
	TAG_COMMENT	=>	'comment',	# Symbol use for comments in the tabular file
	TAG_MULTILINE_SEP	=>	'mult-sep',	# String used to signal multi-line rows
	TAG_SEP		=>	'sep',		# Regular expression separator used for the columns in the tabular file
	TAG_DELIMITER	=>	'delim',	# Symbol used for the columns in the tabular file
	TAG_SKIPLINES	=>	'skip-lines',	# Number of lines to skip at the beginning
	TAG_HAS_HEADER	=>	'read-header',	# Do we expect an embedded header line?
	TAG_HEADER	=>	'header',	# The array of elements in the header
	TAG_NUM_COLS	=>	'num-cols',	# Number of columns, fixed instead of calculated
	TAG_POS_FILTER	=>	'pos-filter',	# Positive filter by these values
	TAG_NEG_FILTER	=>	'neg-filter',	# Negative filter by these values
	TAG_FETCH_COLS	=>	'fetch-cols',	# The columns we are interested in
	TAG_CALLBACK	=>	'cb',		# callback to send tokens to
	TAG_ERR_CALLBACK	=>	'ecb',	# error callback to call
	TAG_CONTEXT	=>	'context',	# context data passed to the callback function
	TAG_FOLLOW	=>	'follow',	# If set, if continues despite return values and the errors
	TAG_VERBOSE	=>	'verbose',	# If set, it is verbose on warnings
};

my %DEFCONFIG = (
#	TabParser::TAG_COMMENT	=>	'#',
	TabParser::TAG_SEP	=>	qr/\t/,
	TabParser::TAG_FOLLOW	=>	1,
);

sub parseTab($;\%);

=head2 mapFilters($\@)

Function to map the filters

=cut
sub mapFilters($\@) {
	my($p_header,$p_filters) = @_;
	
	my $numcols = undef;
	if(ref($p_header) eq 'HASH') {
		$numcols = scalar(keys(%{$p_header}));
	} else {
		$numcols = $p_header;
		$p_header = undef;
	}
	
	my @retval = ();
	foreach my $filter (@{$p_filters}) {
		my @columnFilters = ref($filter->[0]) eq 'ARRAY' ? @{$filter->[0]} : $filter->[0];
		
		my $doCroak = '';
		foreach my $columnFilter (@columnFilters) {
			if($columnFilter =~ /^(?:0|[1-9][0-9]*)$/) {
				if($columnFilter < $numcols) {
					push(@retval,[$columnFilter => $filter->[1]]);
					$doCroak = undef;
					last;
				} else {
					$doCroak .= "Condition out of range: ".$columnFilter.' '.$filter->[1]."\n";
				}
			} elsif(defined($p_header)) {
				if(exists($p_header->{$columnFilter})) {
					push(@retval,[$p_header->{$columnFilter},$filter->[1]]);
					$doCroak = undef;
					last;
				} else {
					$doCroak .= "Condition on unknown column: ".$columnFilter.' '.(defined($filter->[1]) ? $filter->[1] : '(no condition)')."\n";
				}
			} else {
				$doCroak .= "Filter with a named column on an unnamed context: ".join(',',@columnFilters).' '.$filter->[1];
				last;
			}
		}
		
		Carp::croak($doCroak)  if(defined($doCroak));
	}
	
	return @retval;
}

=head2 parseTab($;\%)

parseTab parameters:
	T: the tabular file handle, which is being read
	config: the configuration hash used to teach the parser
		how to work
	callback: the function to call with the read data on each
	err_callback: the function to call when an error happens

=cut
sub parseTab($;\%) {
	my($T,$p_config)=@_;
	
	# Setting up the configuration
	my %config = %DEFCONFIG;
	@config{keys(%{$p_config})} = values(%{$p_config})  if(defined($p_config));
	
	# Number of columns of the tabular file
	# At this point we know nothing...
	my $numcols = undef;
	
	my @header = ();
	my %header = ();
	
	my @posfilter = ();
	my $doPosFilter = exists($config{TabParser::TAG_POS_FILTER});
	
	my @negfilter = ();
	my $doNegFilter = exists($config{TabParser::TAG_NEG_FILTER});
	
	my @columns = ();
	my $doColumns = exists($config{TabParser::TAG_FETCH_COLS});
	
	my $hasContext = exists($config{TabParser::TAG_CONTEXT});
	my $context = $hasContext?$config{TabParser::TAG_CONTEXT}:undef;
	
	my $doFollow = exists($config{TabParser::TAG_FOLLOW}) && $config{TabParser::TAG_FOLLOW};
	my $beVerbose = exists($config{TabParser::TAG_VERBOSE}) && $config{TabParser::TAG_VERBOSE};
	
	my @fetchColumnFilters = ();
	@fetchColumnFilters = map { [$_ => undef] } @{$config{TabParser::TAG_FETCH_COLS}}  if($doColumns);
	
	my $callback = (exists($config{TabParser::TAG_CALLBACK}))?$config{TabParser::TAG_CALLBACK}:undef;
	my $err_callback = (exists($config{TabParser::TAG_ERR_CALLBACK}))?$config{TabParser::TAG_ERR_CALLBACK}:undef;
	
	# If we have a predefined header
	# we can know the number of columns
	if(exists($config{TabParser::TAG_HEADER})) {
		@header = @{$config{TabParser::TAG_HEADER}};
		$numcols = scalar(@header);
		%header = map { $header[$_] => $_ } (0..($numcols-1));
		
		# And we try mapping the filters
		@posfilter = mapFilters(\%header,@{$config{TabParser::TAG_POS_FILTER}})  if($doPosFilter);
		@negfilter = mapFilters(\%header,@{$config{TabParser::TAG_NEG_FILTER}})  if($doNegFilter);
		@columns = map { $_->[0] } mapFilters(\%header,@fetchColumnFilters)  if($doColumns);
	}
	
	# Is number of columns forced?
	# But only if we don't have already a predefined header
	if(exists($config{TabParser::TAG_NUM_COLS}) && !defined($numcols)) {
		$numcols = $config{TabParser::TAG_NUM_COLS};
		@posfilter = mapFilters($numcols,@{$config{TabParser::TAG_POS_FILTER}})  if($doPosFilter);
		@negfilter = mapFilters($numcols,@{$config{TabParser::TAG_NEG_FILTER}})  if($doNegFilter);
		@columns = map { $_->[0] } mapFilters($numcols,@fetchColumnFilters)  if($doColumns);
	}
	
	# Do we have to read/skip a header?
	# But only if we don't know the number of columns
	my $doReadHeader = undef;
	if(exists($config{TabParser::TAG_HAS_HEADER})) {
		$doReadHeader = defined($numcols)?-1:1;
	}
	
	# This is the comment separator
	my $commentSep = undef;
	if(exists($config{TabParser::TAG_COMMENT})) {
		$commentSep = $config{TabParser::TAG_COMMENT};
	}
		
	# This is the multi-line separator
	my $multiSep = undef;
	my $multiSepLength = undef;
	if(exists($config{TabParser::TAG_MULTILINE_SEP})) {
		$multiSep = $config{TabParser::TAG_MULTILINE_SEP};
		$multiSepLength = length($multiSep);
	}
	
	my $eof = undef;
	# Skipping lines
	if(exists($config{TabParser::TAG_SKIPLINES}) && $config{TabParser::TAG_SKIPLINES} > 0) {
		foreach my $counter (1..($config{TabParser::TAG_SKIPLINES})) {
			my $cvline = $T->getline();
			unless(defined($cvline)) {
				$eof = 1;
				last;
			}
		}
	}
	
	# Let's read!
	unless(defined($eof)) {
		# Value delimiters
		my $delim = undef;
		my $delimLength = undef;
		if(exists($config{TabParser::TAG_DELIMITER})) {
			$delim = $config{TabParser::TAG_DELIMITER};
			$delimLength = length($delim);
		}
		
		# Separator is translated into a regexp
		my $sep = $config{TabParser::TAG_SEP};
		# With delimiters, it is wiser to add them to the separation pattern
		if(defined($delim)) {
			$sep = $delim . $sep . $delim;
		}
		unless(ref($sep) eq 'Regexp') {
			$sep = qr/$sep/;
		}
		
		# The columns we are interested in
		my @datacols = ();
		
		# Step 1: getting what we need
		my $cvline = undef;
		my $precvline = defined($multiSep)?'':undef;
		HEADERGET:
		while(!defined($numcols) && ($cvline=$T->getline())) {
			chomp($cvline);
			
			# Trimming comments
			if(defined($commentSep)) {
				my $commentIdx = index($cvline,$commentSep);
				$cvline = substr($cvline,0,$commentIdx)  if($commentIdx!=-1);
			}
			
			# Is it a multi-line?
			if(defined($multiSep)) {
				my $cvlineMinLength = length($cvline)-$multiSepLength;
				if(index($cvline,$multiSep)==$cvlineMinLength) {
					$precvline .= substr($cvline,0,$cvlineMinLength);
					next;
				} else {
					$cvline = $precvline . $cvline;
					$precvline = '';
				}
			}
			
			# And trimming external delimiters
			if(defined($delim)) {
				if(index($cvline,$delim)==0) {
					$cvline = substr($cvline,$delimLength);
				}
				my $rdel = rindex($cvline,$delim);
				if($rdel!=-1) {
					$cvline = substr($cvline,0,$rdel);
				}
			}
			
			next  if(length($cvline)==0);
			
			# Now, let's split the line
			my @tok = split($sep,$cvline,-1);

			# Reading/skipping the header
			if(defined($doReadHeader)) {
				# We record it instead of discarding it
				if($doReadHeader == 1) {
					@header = @tok;
					$numcols = scalar(@tok);
					%header = map { $header[$_] => $_ } (0..($numcols-1));
					
					@posfilter = mapFilters(\%header,@{$config{TabParser::TAG_POS_FILTER}})  if($doPosFilter);
					@negfilter = mapFilters(\%header,@{$config{TabParser::TAG_NEG_FILTER}})  if($doNegFilter);
					@columns = map { $_->[0] } mapFilters(\%header,@fetchColumnFilters)  if($doColumns);
				}
				last HEADERGET;
			}
			
			# Recording/checking the number of columns
			$numcols = scalar(@tok);
			
			@posfilter = mapFilters($numcols,@{$config{TabParser::TAG_POS_FILTER}})  if($doPosFilter);
			@negfilter = mapFilters($numcols,@{$config{TabParser::TAG_NEG_FILTER}})  if($doNegFilter);
			@columns = map { $_->[0] } mapFilters($numcols,@fetchColumnFilters)  if($doColumns);
			
			# And now, let's filter!
			if($doPosFilter) {
				foreach my $filter (@posfilter) {
					last HEADERGET  if($tok[$filter->[0]] ne $filter->[1]);
				}
			}
			
			if($doNegFilter) {
				foreach my $filter (@negfilter) {
					last HEADERGET  if($tok[$filter->[0]] eq $filter->[1]);
				}
			}
			
			# And let's give it to the callback
			if(defined($callback)) {
				my $retval = undef;
				
				eval {
					if($hasContext) {
						if($doColumns) {
							$retval = $callback->($context,@tok[@columns]);
						} else {
							$retval = $callback->($context,@tok);
						}
					} else {
						if($doColumns) {
							$retval = $callback->(@tok[@columns]);
						} else {
							$retval = $callback->(@tok);
						}
					}
				};
				
				# This is a chance to recover from the error condition
				if($@) {
					if(defined($err_callback)) {
						eval {
							if($hasContext) {
								if($doColumns) {
									$retval = $err_callback->($@,$context,@tok[@columns]);
								} else {
									$retval = $err_callback->($@,$context,@tok);
								}
							} else {
								if($doColumns) {
									$retval = $err_callback->($@,@tok[@columns]);
								} else {
									$retval = $err_callback->($@,@tok);
								}
							}
						};
						if($@) {
							if($doFollow) {
								Carp::carp('WARNING_ERR[header line '.($T->input_line_number()-1).']: '.$@)  if($beVerbose);
							} else {
								Carp::croak('ERROR_ERR[header line '.($T->input_line_number()-1).']: '.$@);
							}
						}
					} elsif($doFollow) {
						Carp::carp('WARNING[header]: '.$@)  if($beVerbose);
					} else {
						Carp::croak('ERROR[header]: '.$@);
					}
				}
				$retval = 1  if($doFollow);
				
				return  unless($retval);
			}
			last;
		}

		# Step 2: run as the hell hounds!
		GETLINE:
		while(my $cvline=$T->getline()) {
			chomp($cvline);
			
			# Trimming comments
			if(defined($commentSep)) {
				my $commentIdx = index($cvline,$commentSep);
				$cvline = substr($cvline,0,$commentIdx)  if($commentIdx!=-1);
			}
			
			# Is it a multi-line?
			if(defined($multiSep)) {
				my $cvlineMinLength = length($cvline)-$multiSepLength;
				if(index($cvline,$multiSep)==$cvlineMinLength) {
					$precvline .= substr($cvline,0,$cvlineMinLength);
					next;
				} else {
					$cvline = $precvline . $cvline;
					$precvline = '';
				}
			}
			
			# And trimming external delimiters
			if(defined($delim)) {
				if(index($cvline,$delim)==0) {
					$cvline = substr($cvline,$delimLength);
				}
				my $rdel = rindex($cvline,$delim);
				if($rdel!=-1) {
					$cvline = substr($cvline,0,$rdel);
				}
			}
			
			next  if(length($cvline)==0);
			
			# Now, let's split the line
			my @tok = split($sep,$cvline,-1);
			my $tokLength = scalar(@tok);
			if($tokLength!=$numcols) {
				my $line = "Line ".($T->input_line_number()-1).". Expected $numcols columns, got $tokLength. The guilty line:\n$cvline\n";
				if($doFollow) {
					Carp::carp('WARNING: '.$line)  if($beVerbose);
				} else {
					Carp::croak('ERROR: '.$line);
				}
			}
			
			# And now, let's filter!
			if($doPosFilter) {
				foreach my $filter (@posfilter) {
					next GETLINE  if($tokLength > $filter->[0] && $tok[$filter->[0]] ne $filter->[1]);
				}
			}
			
			if($doNegFilter) {
				foreach my $filter (@negfilter) {
					next GETLINE  if($tokLength > $filter->[0] && $tok[$filter->[0]] eq $filter->[1]);
				}
			}
			
			# And let's give it to the callback
			if(defined($callback)) {
				my $retval = undef;
				
				eval {
					if($hasContext) {
						if($doColumns) {
							$retval = $callback->($context,@tok[@columns]);
						} else {
							$retval = $callback->($context,@tok);
						}
					} else {
						if($doColumns) {
							$retval = $callback->(@tok[@columns]);
						} else {
							$retval = $callback->(@tok);
						}
					}
				};
				
				# This is a chance to recover from the error condition
				if($@) {
					if(defined($err_callback)) {
						eval {
							if($hasContext) {
								if($doColumns) {
									$retval = $err_callback->($@,$context,@tok[@columns]);
								} else {
									$retval = $err_callback->($@,$context,@tok);
								}
							} else {
								if($doColumns) {
									$retval = $err_callback->($@,@tok[@columns]);
								} else {
									$retval = $err_callback->($@,@tok);
								}
							}
						};
						if($@) {
							if($doFollow) {
								Carp::carp('WARNING_ERR[line '.($T->input_line_number()-1).']: '.$@)  if($beVerbose);
							} else {
								Carp::croak('ERROR_ERR[line '.($T->input_line_number()-1).']: '.$@);
							}
						}
					} elsif($doFollow) {
						Carp::carp('WARNING[line '.($T->input_line_number()-1).']: '.$@)  if($beVerbose);
					} else {
						Carp::croak('ERROR[line '.($T->input_line_number()-1).']: '.$@);
					}
				}
				$retval = 1  if($doFollow);
				
				return  unless($retval);
			}
		}
	}
}

=head1 AUTHOR

José M. Fernández E<lt>jose.m.fernandez@bsc.esE<gt>

=head1 COPYRIGHT

The library was initially created several years ago for the data
management tasks in the
L<BLUEPRINT project|http://www.blueprint-epigenome.eu/>. It is generic
and modular enough to be used in other projects.

Copyright 2019- José M. Fernández & Barcelona Supercomputing Center (BSC)

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the LGPL 2.1 terms.

=head1 SEE ALSO

=cut
1;
