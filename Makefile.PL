use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'File::Stream',
    'VERSION_FROM'	=> 'lib/File/Stream.pm', # finds $VERSION
    'PREREQ_PM'		=> {
	    Carp => 0,
	    FileHandle => 0,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/File/Stream.pm', # retrieve abstract from module
       AUTHOR     => 'Steffen Mueller <stream-module at steffen-mueller dot net>') : ()),
);
