use 5.006001;
use ExtUtils::MakeMaker;
use File::ShareDir::Install;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
install_share 'share';
WriteMakefile(
    NAME              => 'eSourceHighlight',
    VERSION_FROM      => 'lib/eSourceHighlight.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM         => {	'Syntax::SourceHighlight' => 0,
			    			'Efl' => 0}, # e.g., Module::Name => 1.1
    BUILD_REQUIRES    => {'File::ShareDir::Install' => 0},
    ABSTRACT_FROM     => 'lib/eSourceHighlight.pm', # retrieve abstract from module
	EXE_FILES		  => ['bin/esource-highlight.pl'],
    AUTHOR            => 'Maximilian <maximilian@>',
    LICENSE           => 'perl',
    #Value must be from legacy list of licenses here
    #https://metacpan.org/pod/Module::Build::API
);


package MY;
use File::ShareDir::Install qw(postamble);
