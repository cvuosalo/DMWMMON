package DMWMMON::SpaceMon::RecordIO;
use strict;
use warnings;
use Data::Dumper;
use DMWMMON::SpaceMon::Record;
use DMWMMON::SpaceMon::UserAgent;
use Math::BigFloat;
use POSIX qw( strftime );

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my %params = (
	STRICT => 1,
	DEBUG => 1,
	VERBOSE => 1,
	DATASVC => 'https://cmsweb.cern.ch/dmwmmon/datasvc',
	);
    my %args = (@_);
    map { if (defined $args{$_}) {$self->{$_} = $args{$_}} else { $self->{$_} = $params{$_}} } keys %params;
    print "I am in ",__PACKAGE__,"->new()\n" if $self->{VERBOSE};
    bless $self, $class;
    return $self;
}

sub dump { return Data::Dumper->Dump([ (shift) ],[ __PACKAGE__ ]); }

sub readFromFile 
{
    my $self = shift;
    my ($file,) = (@_);
    print "RecordIO reading from file: $file\n" if $self->{VERBOSE};
    my $data = do {
	if( open my $fh, '<', $file )
	{ local $/; <$fh> }
	else { undef }
    };    
    my $record;
    eval $data;    
    $self->{VERBOSE} && print "Record read from $file:\n", $record->dump();
    return $record;
}

sub readFromDatasvc
{
    my $self = shift;
    my $node = shift;
    my $timeout = 500;  # do we need this to be an option?
    my %payload = (); # input to data server call
    my ($date, $datasvc_record, $entry,$response, $target, $timestamp);
    print "RecordIO reading $node record from $self->{'DATASVC'}\n";
    # Get data from the server:
    my $pua = DMWMMON::SpaceMon::UserAgent->new ( 
	VERBOSE => $self->{'VERBOSE'},
	DEBUG   => $self->{'DEBUG'},
	URL     => $self->{'DATASVC'},
	FORMAT  => 'perl',
	);
    $pua->timeout ($timeout) if $timeout;
    $pua->Dump() if ($self->{'DEBUG'});
    $pua->CALL('storageusage');
    $payload{node} = $node if $node;
    $target = $pua->target;
    print "DEBUG: now getting last record for $node\n" if ($self->{'DEBUG'});
    $response = $pua->get($target, \%payload);
    print Dumper($response) if ($self->{'DEBUG'});
    if ($pua->response_ok($response)){
	# Create empty record object to save server data into.
	# For multiple nodes/timebins we will need multiple records.
	# Currently it is only the latest upload for the specified node:
	$datasvc_record = DMWMMON::SpaceMon::Record-> new (NODE => $node,);
	#print $response->content();
	#print $datasvc_record;
	#print Data::Dumper->Dump([ $datasvc_record ]) if ($self->{'DEBUG'});
	#$entry= $datasvc_record->{PHEDEX}{NODES}[0];
	#$timestamp = $entry->{'TIMEBINS'}[0]->{'TIMESTAMP'};
	$self->{VERBOSE} && print "Record:  $datasvc_record->dump()";
	return $datasvc_record;
    }else{
	print "$node : no records\n";
	return undef;
    }
}

sub writeToFile
{
    my $self = shift;
    my ($record, $where) = (@_);
    print "I am in ",__PACKAGE__,"->writeToFile()\n" if $self->{VERBOSE};
    print "RecordIO writing to file: $where\n" if $self->{VERBOSE};
    open (my $fh, '>', $where) or die "Could not open file '$where' $!";
    my $dd = Data::Dumper->new(
	[ $record ],
	[ qw(record) ]
	);
    print $fh $dd->Dump();
    # NR: it looks like Dump above empties the dumped object, so I can't
    # print it again into stdout
    close $fh;
}

sub upload
{    
    my $self = shift;
    my ($record) = (@_);
    print "I am in ",__PACKAGE__,"->upload()\n" if $self->{VERBOSE};
    my $result = $self->uploadRecord(
	$ {$record} {'TIMESTAMP'},
	$ {$record} {'NODE'},
	$ {$record} {'DIRS'},
	);
    return $result;
}

sub uploadRecord{
  # Code from Utilities/testSpace/spaceInsert   <<<
  my $self = shift;
  my $timestamp = shift;
  my $node = shift;
  my $hashref = shift; # pass %payload by reference
  # Adding timestamp and node parameters to the upload hash:
  $hashref->{'timestamp'} = $timestamp;
  $hashref->{'node'} = $node;
  $hashref->{'strict'} = $self->{'STRICT'};
  #print payload: 
  #while( my ($k, $v) = each %$hashref ) {
  #   print "key: $k, value: $v.\n";
  #}
  my $method   = 'post';
  my $timeout  = 500;
  my $pua = DMWMMON::SpaceMon::UserAgent->new ( 
      VERBOSE => $self->{'VERBOSE'},
      DEBUG   => $self->{'DEBUG'},
      URL     => $self->{'DATASVC'},
      FORMAT  => 'perl',
      );
  my ($response,$content,$target);
  print "Begin to connect data service.....\n" if ($self->{'DEBUG'});
  $pua->timeout($timeout) if $timeout;
  $pua->CALL('storageinsert');
  #$pua->CALL('auth'); # for testing authentication without writing into the database.
  $target = $pua->target;
  print "[DEBUG] User agent target=$target\n" if ($self->{'DEBUG'});
  $response = $pua->$method($target,$hashref);
  if ( $pua->response_ok($response) )
    {
      # HTTP call returned correctly, print contents and quit...
      no strict 'vars';
      $content = eval($response->content());
      $content = $content->{PHEDEX}{STORAGEINSERT};
      Data::Dumper->Dump([ $content ]);
      foreach $record ( @{$content} ) {
        print "Inserting Record:\n  ",join('  ',map { "$_:$record->{$_}" } sort keys %{$record}),"\n";
      }
    }
  else
    {
      # Something went wrong...
      print "Error from server ",$response->code(),"(",$response->message(),"), output below:\n",
        $response->content(),"\n";
      print "[DEBUG] Web user agent parameters:\n" . Data::Dumper->Dump([ $pua]) if ($self->{'DEBUG'}); 
      die "exiting after failure\n";
    }
  print  "Done!\n";
}

sub uploadRecordFile
{ # Upload record as a file to some Grid enabled storage. 
    my $self = shift;
    my ($record) = (@_);
    print "I am in ",__PACKAGE__,"->uploadRecordFile()\n" if $self->{VERBOSE};
    return;
}

sub show
{
    # Print record NODE, TIMESTAMP is and DIRS hash in a user friendly format
    # and sorted in an alphabetic order 
    # NODE => undef,
    # TIMESTAMP => undef,
    # DIRS => {},
    my $self = shift;
    my ($record) = (@_);
    my ($num, $unit);
     print "I am in ",__PACKAGE__,"->show()\n" if $self->{VERBOSE};
    print "="x40 . "\n";
    print "Node: " . $record->{NODE} . "\n";
    print "Date: " . strftime("%Y-%m-%d %H:%M:%S", localtime($record->{TIMESTAMP} )) . "\n";
    # sort by path:
    foreach (sort keys %{$record->{DIRS}}) {
	($num, $unit ) = toScaledFormat( $record->{DIRS}->{$_} );
	print "$num   $unit     " . $_ . "\n";
    }
    #print $record->dump();
}

sub toScaledFormat {
    my  $bignum = Math::BigFloat->new( shift );
    my  $logbase  = shift   ||  1000;;
    my  $scaling_lower_limit = 10000;
    if( $bignum < $scaling_lower_limit ) {
        return int($bignum);
    }

    my  @sfx = ( '', qw( KB MB GB TB PB EB ZB YB ) );

    my  $log1000  = $bignum->copy->blog($logbase);
    my  $pow1000  = int($log1000);
    my  $wow = exp( ($log1000 - $pow1000) * log($logbase) );

    # It is possible below to round up to our logbase value, which looks
    #   wrong!  If we would, instead bump up to next power set
    if( $wow >= ($logbase-0.5) ) {
        $wow /= $logbase;
        ++$pow1000;
    }
 
    # If we are not using a decimal base, we may need to show 1023KB
    #   or such using four leading digits.  Use an alternate format
    if( $wow >= 1000 ) {  # If four significant digits
        return( sprintf("%.4g",$wow), $sfx[$pow1000] );
    } else {
        return( sprintf("%.3g",$wow), $sfx[$pow1000] );
    }
}

1;
