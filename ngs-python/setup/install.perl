use strict;

require 'install.prl';

use Config;
use Cwd        "abs_path";
use File::Copy "copy";
use File::Copy::Recursive qw(dircopy);
use File::Path   "make_path";
use FindBin    qw($Bin);
use Getopt::Long "GetOptions";

my %HAVE = HAVE();
++$HAVE{INCLUDES} if ($HAVE{LIBS});
++$HAVE{USR_INCLUDES} if ($HAVE{INCLUDES} && PACKAGE_NAME() eq 'NGS-SDK');

my @bits;
my @options = ('debug', 'examplesdir=s', 'force', 'help',
               'includedir=s', 'no-create', 'prefix=s');
push @options, 'oldincludedir=s' if ($HAVE{USR_INCLUDES});
if ($HAVE{JAR}) {
    push @options, 'jardir=s';
    if (-e "$Bin/../jar") {
        ++$HAVE{LIBS};
        $_{JARDIR} = expand_path("$Bin/../jar");
    }
} elsif ($HAVE{PYTHON} && -e "$Bin/../lib64") {
    ++$HAVE{LIBS};
}
push @options, 'bits=s' => \@bits, 'libdir=s' if ($HAVE{LIBS});

my %OPT;
unless (GetOptions(\%OPT, @options)) {
    print "install: error\n";
    exit 1;
}
@bits = split(/,/,join(',',@bits));
foreach (@bits) {
    unless (/^32$/ || /^64$/) {
        print "install: error: bad bits option argument value\n";
        exit 1;
    }
}
if ($#bits > 0 && $OPT{libdir}) {
    print "install: error: cannot supply multiple bits arguments "
        . "when libdir argument is provided\n";
    exit 1;
}

my $OS;
{
    my $file = 'os.prl';
    if (-e $file) {
        require $file;
        $OS = OS();
    } else {
        ++$OPT{making};
    }
}

prepare();

@_ = CONFIGURE();

foreach (qw(BITS INCDIR INST_INCDIR INST_JARDIR INST_LIBDIR INST_SHAREDIR
            LIBX LPFX MAJVERS MAJVERS_SHLX OS OTHER_PREFIX
            PACKAGE_NAME PREFIX SHLX VERSION VERSION_LIBX VERSION_SHLX))
{
    unless ($_{$_}) {
        next if (/^INST_JARDIR$/ && ! $HAVE{JAR});
        fatal_config("$_ not found");
    }
}
unless ($_{LIBDIR32} || $_{LIBDIR64} || ($HAVE{PYTHON} && $OPT{making})) {
    fatal_config('LIBDIR not found');
}
 
my $LINUX_ROOT;
if ($_{OS} eq 'linux' && `id -u` == 0) {
    ++$LINUX_ROOT;
}
my $ROOT = '';
#$ROOT = "$ENV{HOME}/ROOT"; ++$LINUX_ROOT;
my $oldincludedir = "$ROOT/usr/include";

my $EXAMPLES_DIR = "$Bin/../examples";

if ($OPT{help}) {
    help();
    exit 0;
}

if ($OPT{prefix}) {
    $OPT{prefix} = expand_path($OPT{prefix});
    $_{INST_LIBDIR  } = "$OPT{prefix}/lib";
    $_{INST_INCDIR  } = "$OPT{prefix}/include";
    $_{INST_JARDIR  } = "$OPT{prefix}/jar";
    $_{INST_SHAREDIR} = "$OPT{prefix}/share";
}
$_{LIB_TARGET   } = expand_path($OPT{libdir       }) if ($OPT{libdir       });
$_{INST_SHAREDIR} = expand_path($OPT{examplesdir  }) if ($OPT{examplesdir  });
$_{INST_INCDIR  } = expand_path($OPT{includedir   }) if ($OPT{includedir   });
$_{INST_JARDIR  } = expand_path($OPT{jardir       }) if ($OPT{jardir   });
$oldincludedir    = expand_path($OPT{oldincludedir}) if ($OPT{oldincludedir});
$_{JAR_TARGET   } = "$_{INST_JARDIR}/ngs-java.jar";

if ($OPT{'no-create'} && $_{OS} eq 'linux') {
    if ($LINUX_ROOT) {
        print "root user\n\n";
    } else {
        print "non root user\n\n";
    }
}

my $failures = 0;
my $bFailure = 1;

push @bits, $_{BITS} unless (@bits);
foreach (@bits) {
    $_{BITS} = $_;

    print "installing $_{PACKAGE_NAME} ($_{VERSION}) package";
    print " for $_{OS}-$_{BITS}" if ($HAVE{LIBS});
    print "...\n";

    if ($HAVE{LIBS} || $HAVE{PYTHON}) {
        $_{LIBDIR} = $_{"LIBDIR$_{BITS}"};
        unless ($_{LIBDIR}) {
            print "install: error: $_{BITS}-bit version is not available\n\n";
            next;
        }
    }
    if ($HAVE{JAR} && ! $_{JARDIR}) {
        $_{JARDIR} = $_{"LIBDIR$_{BITS}"};
        unless ($_{JARDIR}) {
            if ($_{BITS} == 64) {
                $_{JARDIR} = $_{LIBDIR32};
            } else {
                $_{JARDIR} = $_{LIBDIR64};
            }
            unless ($_{JARDIR}) {
                print "install: error: jar file was not cannot found\n";
                exit 1;
            }
        }
    }
    $bFailure = 0;

    if ($OPT{'no-create'}) {
        print     "libdir     : '$_{INST_LIBDIR}$_{BITS}'\n" if ($HAVE{LIBS});
        print     "includedir : '$_{INST_INCDIR  }'\n" if ($HAVE{INCLUDES});
        print     "jardir     : '$_{INST_JARDIR  }'\n" if ($HAVE{JAR });
        print     "examplesdir: '$_{INST_SHAREDIR}'\n";
        if ($LINUX_ROOT) {
            print "oldincludedir: '$oldincludedir'\n"  if ($HAVE{USR_INCLUDES});
        }
        print "\n";
        next;
    }

    $_{LIB_TARGET} = "$_{INST_LIBDIR}$_{BITS}" unless ($OPT{libdir});

    $File::Copy::Recursive::CPRFComp = 1;

    $failures += copylibs    () if ($HAVE{LIBS});
    $failures += copyincludes() if ($HAVE{INCLUDES});
    $failures += copyjars    () if ($HAVE{JAR});

    if ($HAVE{JAR}) {
        $File::Copy::Recursive::CPRFComp = 0;
        $failures += copydocs() ;
        $File::Copy::Recursive::CPRFComp = 1;
    }

    $failures += copyexamples();
    $File::Copy::Recursive::CPRFComp = 1; # could be reset in copyexamples
    $failures += finishinstall() unless ($failures);

    unless ($failures) {
        print "\nsuccessfully installed $_{PACKAGE_NAME} ($_{VERSION}) package";
    } else {
        print "\nfailed to install $_{PACKAGE_NAME} ($_{VERSION}) package";
    }
    print " for $_{OS}-$_{BITS}" if ($HAVE{LIBS});
    print ".\n\n";
}

$failures = 1 if (!$failures && $bFailure);

exit $failures;

################################################################################

sub copylibs {
    my $s = $_{LIBDIR};
    my $d = $_{LIB_TARGET};

    print "installing libraries to $d... ";

    unless (-e $s) {
        print "\tfailure\n";
        print "install: error: '$s' is not found.\n";
        return 1;
    }

    print "\nchecking $d... ";
    unless (-e $d) {
        print "not found\n";
        print "mkdir -p $d... ";
        eval { make_path($d) };
        if ($@) {
            print "failure\ninstall: error: cannot mkdir $d\n";
            return 1;
        } else {
            print "success\n";
        }
    } else {
        print "exists\n";
    }

    print "\t\tcd $d\n" if ($OPT{debug});
    chdir $d or die "cannot cd $d";

    return $OPT{making} ? copybldlibs() : copydir($_{LIBDIR});
}

sub copybldlibs {
    my $failures = 0;

    my %LIBRARIES_TO_INSTALL =
        ('ngs-sdk' => 'SHL', 'ngs-c++' => 'LIB', 'ngs-adapt-c++' => 'LIB');
    foreach (keys %LIBRARIES_TO_INSTALL) {
        print "installing '$_'... ";

        my $nb = "$_{LPFX}$_";
        my $nv = "$nb.";
        my $lib = 'dll';
        if ($LIBRARIES_TO_INSTALL{$_} eq 'SHL') {
            $nv .= $_{VERSION_SHLX};
        } elsif ($LIBRARIES_TO_INSTALL{$_} eq 'LIB') {
            $nv .= $_{VERSION_LIBX};
            $lib = 'lib';
        } else {
            die "bad library type";
        }

        my $s = "$_{LIBDIR}/$nv";
        my $d = "$_{LIB_TARGET}/$nv";

        print "\n\t\t$s -> $d\n\t" if ($OPT{debug});

        unless (-e $s) {
            print "failure\n";
            print "install: error: '$s' is not found.\n";
            ++$failures;
            next;
        }

        if ((! $OPT{force}) && (-e $d) && (-M $d < -M $s)) {
            print "found\n";
        } else {
            unless (copy($s, $d)) {
                print "failure\n";
                print "install: error: cannot copy '$s' '$d'.\n";
                ++$failures;
                next;
            }
            my $mode = 0644;
            $mode = 0755 if ($lib eq 'dll');
            printf "\tchmod %o $d\n\t", $mode if ($OPT{debug});
            unless (chmod($mode, $d)) {
                print "failure\n";
                print "install: error: cannot chmod '$d': $!\n";
                ++$failures;
                next;
            }
            unless (symlinks($nb, $nv, $lib)) {
                print "success\n";
            } else {
                print "failure\n";
                ++$failures;
            }
        }
    }
    
    return $failures;
}

sub symlinks {
    my ($nb, $nv, $lib) = @_;
 
    my @l;
    if ($lib eq 'lib') {
        push @l, "$nb-static.$_{LIBX}";
        push @l, "$nb.$_{LIBX}";
        push @l, "$nb.$_{MAJVERS_LIBX}";
    } elsif ($lib eq 'dll') {
        push @l, "$nb.$_{SHLX}";
        push @l, "$nb.$_{MAJVERS_SHLX}";
    } elsif ($lib eq 'jar') {
        push @l, $nb;
        push @l, "$nb.$_{MAJVERS}";
    } else {
        print "failure\n";
        print "install: error: unknown symlink type '$lib'\n";
        return 1;
    }
 
    my $failures = 0;
 
    for (my $i = 0; $i <= $#l; ++$i) {
        my $file = $l[$i];
        if (-e $file) {
            print "\trm $file\n\t" if ($OPT{debug});
            unless (unlink $file) {
                print "failure\n";
                print "install: error: cannot rm '$file': $!\n";
                ++$failures;
                next;
            }
        }
 
        my $o = $nv;
        $o = $l[$i + 1] if ($i < $#l);
 
        print "\tln -s $o $file\n\t" if ($OPT{debug});
        unless (symlink $o, $file) {
            print "failure\n";
            print "install: error: cannot symlink '$o' '$file': $!\n";
            ++$failures;
            next;
        }
    }

    return $failures;
}

sub copydir {
    my ($s) = @_;

    my $failures = 0;

    opendir(D, $s) or die "cannot opendir $s: $!";

    while (readdir D) {
        next if (/^\.{1,2}$/);

        my $n = "$s/$_";

        if (-l $n) {
            print "\t\t$_ (symlink)... " if ($OPT{debug});
            my $l = readlink $n;
            if ((-e $_) && (!unlink $_)) {
                print "error: cannot remove $l: $!\n";
                ++$failures;
                next;
            }
            unless (symlink($l, $_)) {
                print
                    "error: cannot create symlink from $_ to $l: $!\n";
                ++$failures;
                next;
            }
            print "success\n" if ($OPT{debug});
        } else {
            print "\t\t$_... " if ($OPT{debug});
            if ((-e $_) && (!unlink $_)) {
                print "error: cannot remove $_: $!\n";
                ++$failures;
                next;
            }
            unless (copy($n, $_)) {
                print "error: cannot copy '$n' to '$_': $!\n";
                ++$failures;
                next;
            }
            print "success\n" if ($OPT{debug});
        }
    }

    closedir D;

    return $failures;
}

sub copyincludes {
    print "installing includes to $_{INST_INCDIR}... ";

    my $s = "$_{INCDIR}/ngs";
    unless (-e $s) {
        print "\tfailure\n";
        print "install: error: '$s' is not found.\n";
        return 1;
    }

    unless (-e $_{INST_INCDIR}) {
        print "\n\t\tmkdir -p $_{INST_INCDIR}" if ($OPT{debug});
        eval { make_path($_{INST_INCDIR}) };
        if ($@) {
            print "\tfailure\ninstall: error: cannot mkdir $_{INST_INCDIR}";
            return 1;
        }
    }

    print "\n\t\tcp -r $s $_{INST_INCDIR}\n\t" if ($OPT{debug});
    unless (dircopy($s, $_{INST_INCDIR})) {
        print "\tfailure\ninstall: error: "
            . "cannot copy '$s' '$_{INST_INCDIR}'";
        return 1;
    }

    print "success\n";
    return 0;
}

sub copyjars {
    my $s = $_{JARDIR};
    my $d = $_{INST_JARDIR};

    print "installing jar files to $d... ";

    unless (-e $s) {
        print "\tfailure\n";
        print "install: error: '$s' is not found.\n";
        return 1;
    }

    print "\nchecking $d... ";
    unless (-e $d) {
        print "not found\n";
        print "mkdir -p $d... ";
        eval { make_path($d) };
        if ($@) {
            print "failure\ninstall: error: cannot mkdir $d\n";
            return 1;
        } else {
            print "success\n";
        }
    } else {
        print "exists\n";
    }

    print "\t\tcd $d\n" if ($OPT{debug});
    chdir $d or die "cannot cd $d";

    return $OPT{making} ? copybldjars($s, $d) : copydir($s);
}

sub copybldjars{
    my ($s, $d) = @_;
    my $n = 'ngs-java.jar';
    $s .= "/$n";

    unless (-e $s) {
        print "\tfailure\n";
        print "install: error: '$s' is not found.\n";
        return 1;
    }

    my $nd = "$n.$_{VERSION}";
    print "installing '$n'... ";

    $d .= "/$nd";

    print "\n\t\t$s -> $d\n\t" if ($OPT{debug});

    if ((! $OPT{force}) && (-e $d) && (-M $d < -M $s)) {
        print "found\n";
    } else {
        unless (copy($s, $d)) {
            print "failure\n";
            print "install: error: cannot copy '$s' '$d'.\n";
            return 1;
        }
        my $mode = 0644;
        printf "\tchmod %o $d\n\t", $mode if ($OPT{debug});
        unless (chmod($mode, $d)) {
            print "failure\n";
            print "install: error: cannot chmod '$d': $!\n";
            return 1;
        }
        unless (symlinks($n, $nd, 'jar')) {
            print "success\n";
        } else {
            print "failure\n";
            return 1;
        }
    }

    return 0;
}

sub copydocs {
    my $s = "$_{JARDIR}/javadoc";
    $s = expand_path("$Bin/../doc") unless ($OPT{making});
    my $d = "$_{INST_SHAREDIR}/doc";

    print "installing html documents to $d... ";

    unless (-e $s) {
        print "\tfailure\n";
        print "install: error: '$s' is not found.\n";
        return 1;
    }

    print "\nchecking $d... ";
    unless (-e $d) {
        print "not found\n";
        print "mkdir -p $d... ";
        eval { make_path($d) };
        if ($@) {
            print "failure\ninstall: error: cannot mkdir $d";
            return 1;
        } else {
            print "success\n";
        }
    } else {
        print "exists\n";
    }

    print "\t\t$s -> $d\n\t" if ($OPT{debug});
    unless (dircopy($s, $d)) {
        print "\tfailure\ninstall: error: cannot copy '$s' to '$d'";
        return 1;
    }

    print "success\n";
    return 0;
}

sub copyexamples {
    my $sd = $EXAMPLES_DIR;
    return 0 unless (-e $sd);

    my $d = $_{INST_SHAREDIR};
    if ($HAVE{JAR}) {
        $d .= '/examples-java';
    } elsif ($HAVE{PYTHON}) {
        $File::Copy::Recursive::CPRFComp = 0;
        $d .= '/examples-python';
    }

    print "installing examples to $d... ";

    my $s = $sd;
    $s = "$sd/examples" if ($HAVE{JAR} && $OPT{making});

    unless (-e $s) {
        print "\tfailure\n";
        print "install: error: '$s' is not found.\n";
        return 1;
    }

    print "\nchecking $d... ";
    unless (-e $d) {
        print "not found\n";
        print "mkdir -p $d... ";
        eval { make_path($d) };
        if ($@) {
            print "failure\ninstall: error: cannot mkdir $d";
            return 1;
        } else {
            print "success\n";
        }
    } else {
        print "exists\n";
    }

    print "\t\t$s -> $d\n\t" if ($OPT{debug});
    unless (dircopy($s, $d)) {
        print "\tfailure\ninstall: error: cannot copy '$s' to '$d'";
        return 1;
    }

    if ($HAVE{JAR} && $OPT{making}) {
        $sd = "$sd/Makefile";
        $d = "$d/Makefile";
        print "\t$sd -> $d\n\t" if ($OPT{debug});
        unless (-e $sd) {
            print "\tfailure\n";
            print "install: error: '$sd' is not found.\n";
            return 1;
        }
        if (-e $d) {
            unless (unlink $d) {
                print "failure\n";
                print "install: error: cannot rm '$d': $!\n";
                return 1;
            }
        }
        unless (copy($sd, $d)) {
            print "error: cannot copy '$sd' to '$d': $!\n";
            return 1;
        }
    }

    print "success\n";
    return 0;
}

sub finishinstall {
    my $failures = 0;

    if ($HAVE{PYTHON}) {
        chdir "$Bin/.." or die "cannot cd '$Bin/..'";
        my $cmd = "python setup.py install";
        $cmd .= ' --user' unless ($LINUX_ROOT);
        print `$cmd`;
        if ($?) {
            ++$failures;
        } else {
            if ($HAVE{LIBS}) {
                $_ = $_{LIB_TARGET};
            } else {
                $_ = $_{LIBDIR};
            }
            print <<EndText;
Please add $_ to your LD_LIBRARY_PATH, e.g.:
      export LD_LIBRARY_PATH=$_:\$LD_LIBRARY_PATH
EndText
      }
    } elsif ($LINUX_ROOT) {
        print "\t\tlinux root\n" if ($OPT{debug});

        if ($HAVE{USR_INCLUDES}) {
            unless (-e $oldincludedir) {
                print "install: error: '$oldincludedir' does not exist\n";
                ++$failures;
            } else {
                my $INCLUDE_SYMLINK = "$oldincludedir/ngs";
                print "updating $INCLUDE_SYMLINK... ";
                unlink $INCLUDE_SYMLINK;
                my $o = "$_{INST_INCDIR}/ngs";
                unless (symlink $o, $INCLUDE_SYMLINK) {
                    print "failure\n";
                    print "install: error: "
                        . "cannot symlink '$o' '$INCLUDE_SYMLINK': $!\n";
                    ++$failures;
                } else {
                    print "success\n";
                }
            }
        }

        my $profile = "$ROOT/etc/profile.d";
        my $PROFILE_FILE = "$profile/ngs-sdk";
        $PROFILE_FILE = "$profile/ngs-java" if ($HAVE{JAR});
        unless (-e $profile) {
            print "install: error: '$profile' does not exist\n";
            ++$failures;
        } else {
            print "updating $PROFILE_FILE.[c]sh... ";

            my $f = "$PROFILE_FILE.sh";
            if (!open F, ">$f") {
                print "failure\n";
                print "install: error: cannot open '$f': $!\n";
                ++$failures;
            } else {
                if ($HAVE{LIBS}) {
                    print F <<EndText;
#version $_{VERSION}
if ! echo \$LD_LIBRARY_PATH | /bin/grep -q $_{LIB_TARGET}
then export LD_LIBRARY_PATH=$_{LIB_TARGET}:\$LD_LIBRARY_PATH
fi
export NGS_LIBDIR=$_{LIB_TARGET}
EndText
                } else {
                    print F <<EndText;
#version $_{VERSION}
if ! echo \$CLASSPATH | /bin/grep -q $_{JAR_TARGET}
then export CLASSPATH=$_{JAR_TARGET}:\$CLASSPATH
fi
EndText
                }
                close F;
                unless (chmod(0644, $f)) {
                    print "failure\n";
                    print "install: error: cannot chmod '$f': $!\n";
                    ++$failures;
                }
            }
        }

        my $f = "$PROFILE_FILE.csh";
        if (!open F, ">$f") {
            print "failure\n";
            print "install: error: cannot open '$f': $!\n";
            ++$failures;
        } else {
            if ($HAVE{LIBS}) {
                print F <<EndText;
#version $_{VERSION}
echo \$LD_LIBRARY_PATH | /bin/grep -q $_{LIB_TARGET}
if ( \$status ) setenv LD_LIBRARY_PATH $_{LIB_TARGET}:\$LD_LIBRARY_PATH
setenv NGS_LIBDIR $_{LIB_TARGET}
EndText
            } else {
                print F <<EndText;
#version $_{VERSION}
echo \$CLASSPATH | /bin/grep -q $_{JAR_TARGET}
if ( \$status ) setenv CLASSPATH $_{JAR_TARGET}:\$CLASSPATH
EndText
            }
            close F;
            unless (chmod(0644, $f)) {
                print "failure\n";
                print "install: error: cannot chmod '$f': $!\n";
                ++$failures;
            }
        }
#	@ #TODO: check version of the files above

        unless ($failures) {
            print "success\n";

            if ($HAVE{LIBS}) {
                print "\nUse \$NGS_LIBDIR in your link commands, e.g.:\n";
                print "      ld -L\$NGS_LIBDIR -lngs-sdk ...\n";
            }
        }
    } else {
        print "\t\tnot linux root\n" if ($OPT{debug});
        if ($HAVE{LIBS}) {
            print <<EndText;

Please add $_{LIB_TARGET} to your LD_LIBRARY_PATH, e.g.:
      export LD_LIBRARY_PATH=$_{LIB_TARGET}:\$LD_LIBRARY_PATH
Use $_{LIB_TARGET} in your link commands, e.g.:
      export NGS_LIBDIR=$_{LIB_TARGET}
      ld -L\$NGS_LIBDIR -lngs-sdk ...
EndText
        } elsif ($HAVE{JAR}) {
            print <<EndText;

Please add $_{JAR_TARGET} to your CLASSPATH, i.e.:
      export CLASSPATH=$_{JAR_TARGET}:\$CLASSPATH
EndText
        }
    }

    return $failures;
}

sub expand_path {
    my ($filename) = @_;
    return unless ($filename);

    if ($filename =~ /^~/) {
        if ($filename =~ m|^~([^/]*)|) {
            if ($1 && ! getpwnam($1)) {
                print "install: error: bad path: '$filename'\n";
                exit 1;
            }
        }

        $filename =~ s{ ^ ~ ( [^/]* ) }
                      { $1
                            ? (getpwnam($1))[7]
                            : ( $ENV{HOME} || $ENV{USERPROFILE} || $ENV{LOGDIR}
                                || (getpwuid($<))[7]
                              )
                      }ex;
    }

    my $a = abs_path($filename);
    $filename = $a if ($a);

    $filename;
}

sub help {
    $_{LIB_TARGET} = "$_{INST_LIBDIR}$_{BITS}";

    print <<EndText;
'install' installs $_{PACKAGE_NAME} $_{VERSION} package.

Usage: ./install [OPTION]...

Defaults for the options are specified in brackets.

Configuration:
  -h, --help              display this help and exit
  -n, --no-create         do not run installation

Installation directories:
  --prefix=PREFIX         install all files in PREFIX
                          [$_{PREFIX}]

By default, `./install' will install all the files in
EndText

    if ($HAVE{INCLUDES}) {
        print
        "`$_{PREFIX}/include', `$_{PREFIX}/lib$_{BITS}' etc.  You can specify\n"
    } elsif ($HAVE{JAR}) {
        print
        "`$_{PREFIX}/jar', `$_{PREFIX}/share' etc.  You can specify\n"
    } elsif ($OPT{making}) {
        print "`$_{PREFIX}/share' etc.  You can specify\n"
    } else {
        print
           "`$_{PREFIX}/lib$_{BITS}' `$_{PREFIX}/share' etc.  You can specify\n"
    }

    print <<EndText;
an installation prefix other than `$_{PREFIX}' using `--prefix',
for instance `--prefix=$_{OTHER_PREFIX}'.

For better control, use the options below.

Fine tuning of the installation directories:
EndText

    if ($HAVE{JAR}) {
        print "  --jardir=DIR            jar files [PREFIX/jar]\n";
    }
    if ($HAVE{LIBS}) {
        print
        "  --libdir=DIR            object code libraries [PREFIX/lib$_{BITS}]\n"
    }
    if ($HAVE{INCLUDES}) {
        print "  --includedir=DIR        C header files [PREFIX/include]\n";
    }
    if ($HAVE{USR_INCLUDES}) {
        print
       "  --oldincludedir=DIR     C header files for non-gcc [$oldincludedir]\n"
    }

    if (-e $EXAMPLES_DIR) {
        print "  --examplesdir=DIR       example files [PREFIX/share]\n";
    }

    if ($HAVE{LIBS}) {
        print <<EndText;

System types:
  --bits=[32|64]          use a 32- or 64-bit data model
EndText
    }

    print "\nReport bugs to sra-tools\@ncbi.nlm.nih.gov\n";
}

sub prepare {
    if ($OPT{making}) {
        my $os_arch = `perl -w $Bin/os-arch.perl`;
        unless ($os_arch) {
            print "install: error\n";
            exit 1;
        }
        chomp $os_arch;
        my $config = "$Bin/../Makefile.config.install.$os_arch.prl";
        fatal_config("$config not found") unless (-e "$config");

        eval { require $config; };
        fatal_config($@) if ($@);
    } else {
        my $a = $Config{archname64};
        $_ = lc PACKAGE_NAME();
        my $code = 
            'sub CONFIGURE { ' .
            '   $_{OS           } = $OS; ' .
            '   $_{VERSION      } = "1.0.0"; ' .
            '   $_{MAJVERS      } = "1"; ' .
            '   $_{LPFX         } = "lib"; ' .
            '   $_{LIBX         } = "a"; ' .
            '   $_{MAJVERS_LIBX } = "a.1"; ' .
            '   $_{VERSION_LIBX } = "a.1.0.0"; ' .
            '   $_{SHLX         } = "so"; ' .
            '   $_{OTHER_PREFIX } = \'$HOME/ngs/' . $_ . '\'; ' .
            '   $_{PREFIX       } = "/usr/local/ngs/' . $_ . '"; ' .
            '   $_{INST_INCDIR  } = "$_{PREFIX}/include"; ' .
            '   $_{INST_LIBDIR  } = "$_{PREFIX}/lib"; ' .
            '   $_{INST_JARDIR  } = "$_{PREFIX}/jar"; ' .
            '   $_{INST_SHAREDIR} = "$_{PREFIX}/share"; ' .
            '   $_{INCDIR       } = "$Bin/../include"; ' .
            '   $_{LIBDIR64     } = "$Bin/../lib64"; ' .
            '   $_{LIBDIR32     } = "$Bin/../lib32"; ';

        $code .= ' $_{PACKAGE_NAME} = "' . PACKAGE_NAME() . '"; ';

        if (defined $Config{archname64}) {
            $code .= ' $_{BITS} = 64; ';
        } else {
            $code .= ' $_{BITS} = 32; ';
        }

        $code .= 
            '   $_{MAJVERS_SHLX } = "so.1"; ' .
            '   $_{VERSION_SHLX } = "so.1.0.0"; ' ;

        $code .= 
            '   @_ ' .
            '}';

        eval $code;

        die $@ if ($@);
    }
}

sub fatal_config {
    if ($OPT{debug}) {
        print "\t\t";
        print "@_";
        print "\n";
    }

    print "install: error: run ./configure [OPTIONS] first.\n";

    exit 1;
}

################################################################################