# NAME

TabParser - A parser of tabulated or comma separated value files

# SYNOPSIS

    use TabParser;

# DESCRIPTION

TabParser is a library which eases parsing tabular files (or data
streams), using the least possible memory and calling callbacks defined
before parsing task.

## mapFilters($\\@)

Function to map the filters

## parseTab($;\\%)

parseTab parameters:
	T: the tabular file handle, which is being read
	config: the configuration hash used to teach the parser
		how to work
	callback: the function to call with the read data on each
	err\_callback: the function to call when an error happens

# AUTHOR

José M. Fernández <jose.m.fernandez@bsc.es>

# COPYRIGHT

The library was initially created several years ago for the data
management tasks in the
[BLUEPRINT project](http://www.blueprint-epigenome.eu/). It is generic
and modular enough to be used in other projects.

Copyright 2019- José M. Fernández & Barcelona Supercomputing Center (BSC)

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the LGPL 2.1 terms.

# SEE ALSO
