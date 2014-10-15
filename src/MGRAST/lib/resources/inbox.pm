package resources::inbox;

use strict;
use warnings;
no warnings('once');

use POSIX qw(strftime);
use HTTP::Request::StreamingUpload;
use HTTP::Headers;
use LWP::UserAgent;
use Data::Dumper;
use Template;

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name
    $self->{name} = "inbox";
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name' => $self->name,
        'url' => $self->cgi->url."/".$self->name,
        'description' => "inbox receives user inbox data upload, requires authentication, see http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#api_submission for details",
        'type' => 'object',
        'documentation' => $self->cgi->url.'/api.html#'.$self->name,
        'requests' => [
            { 'name'        => "info",
              'request'     => $self->cgi->url."/".$self->name,
              'description' => "Returns description of parameters and attributes.",
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => "self",
              'parameters'  => {
                  'options'  => {},
                  'required' => {},
                  'body'     => {}
              }
            },
            { 'name'        => "view",
              'request'     => $self->cgi->url."/".$self->name,
              'description' => "lists the contents of the user inbox",
              'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->cgi->url."/".$self->name.'"',
                  			     'lists the contents of the user inbox, auth is required' ],
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => {
                  'id'        => [ 'string', "user id" ],
                  'user'      => [ 'string', "user name" ],
                  'timestamp' => [ 'string', "timestamp for return of this query" ],
                  'files'     => [ 'list', [ 'object', [
                                                { 'filename'  => [ 'string', "path of file from within user inbox" ],
                                                  'filesize'  => [ 'string', "disk size of file in bytes" ],
                                                  'checksum'  => [ 'string', "md5 checksum of file"],
                                                  'timestamp' => [ 'string', "timestamp of file" ]
                                                }, "list of file objects"] ] ],
                  'url'       => [ 'uri', "resource location of this object instance" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "upload",
              'request'     => $self->cgi->url."/".$self->name,
              'description' => "receives user inbox data upload",
              'example'     => [ 'curl -X POST -H "auth: auth_key" -F "upload=@sequences.fastq" "'.$self->cgi->url."/".$self->name.'"',
                    			 "upload file 'sequences.fastq' to user inbox, auth is required" ],
              'method'      => "POST",
              'type'        => "synchronous",
              'attributes'  => {
                  'id'        => [ 'string', "user id" ],
                  'user'      => [ 'string', "user name" ],
                  'status'    => [ 'string', "status message" ],
                  'timestamp' => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => { "upload" => ["file", "file to upload to inbox"] }
              }
            },
            { 'name'        => "file_info",
              'request'     => $self->cgi->url."/".$self->name."/info/{UUID}",
              'description' => "get basic file info - returns results and updates shock node",
              'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->cgi->url."/".$self->name.'/info/cfb3d9e1-c9ba-4260-95bf-e410c57b1e49"',
                                 "get basic info for file with given id in user inbox, auth is required" ],
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => {
                  'id'         => [ 'string', "user login" ],
                  'user'       => [ 'string', "user name" ],
                  'stats_info' => [ 'hash', 'key value pairs describing file info' ],
                  'status'     => [ 'string', "status message" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ],
                                  "uuid" => [ "string", "RFC 4122 UUID for file" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "seq_stats",
              'request'     => $self->cgi->url."/".$self->name."/stats/{UUID}",
              'description' => "runs sequence stats on file in user inbox - submits AWE job",
              'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->cgi->url."/".$self->name.'/stats/cfb3d9e1-c9ba-4260-95bf-e410c57b1e49"',
                                 "runs seq stats on file with given id in user inbox, auth is required" ],
              'method'      => "GET",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'        => [ 'string', "user login" ],
                  'user'      => [ 'string', "user name" ],
                  'awe_id'    => [ 'string', "url/id of awe job" ],
                  'status'    => [ 'string', "status message" ],
                  'timestamp' => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ],
                                  "uuid" => [ "string", "RFC 4122 UUID for sequence file" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "sff_to_fastq",
              'request'     => $self->cgi->url."/".$self->name."/sff2fastq",
              'description' => "create fastq file from sff file - submits AWE job",
              'example'     => [ 'curl -X POST -H "auth: auth_key" -F "sff_file=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" "'.$self->cgi->url."/".$self->name.'/sff2fastq"',
                                 "create fastq file from sff file with given id in user inbox, auth is required" ],
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'        => [ 'string', "user login" ],
                  'user'      => [ 'string', "user name" ],
                  'awe_id'    => [ 'string', "url/id of awe job" ],
                  'status'    => [ 'string', "status message" ],
                  'timestamp' => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => { "sff_file" => [ "string", "RFC 4122 UUID for sff file" ] }
              }
            },
            { 'name'        => "demultiplex",
              'request'     => $self->cgi->url."/".$self->name."/demultiplex",
              'description' => "demultiplex seq file with barcode file - submits AWE job",
              'example'     => [ 'curl -X POST -H "auth: auth_key" -F "seq_file=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" -F "barcode_file=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" "'.$self->cgi->url."/".$self->name.'/demultiplex"',
                                 "demultiplex seq file with barcode file for given ids in user inbox, auth is required" ],
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'        => [ 'string', "user login" ],
                  'user'      => [ 'string', "user name" ],
                  'awe_id'    => [ 'string', "url/id of awe job" ],
                  'status'    => [ 'string', "status message" ],
                  'timestamp' => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => { "seq_file"      => [ "string", "RFC 4122 UUID for sequence file" ],
                                  "barcode_file"  => [ "string", "RFC 4122 UUID for barcode file" ],
                                  "barcode_count" => [ "int", "number of unique barcodes in barcode_file" ] }
              }
            },
            { 'name'        => "pair_join",
              'request'     => $self->cgi->url."/".$self->name."/pairjoin",
              'description' => "merge overlapping paired-end fastq files - submits AWE job",
              'example'     => [ 'curl -X POST -H "auth: auth_key" -F "retain=1" -F "pair_file_1=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" -F "pair_file_2=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" "'.$self->cgi->url."/".$self->name.'/pairjoin"',
                                 "merge overlapping paired-end fastq files for given ids, retain non-overlapping pairs" ],
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'        => [ 'string', "user login" ],
                  'user'      => [ 'string', "user name" ],
                  'awe_id'    => [ 'string', "url/id of awe job" ],
                  'status'    => [ 'string', "status message" ],
                  'timestamp' => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => { "pair_file_1" => [ "string", "RFC 4122 UUID for pair 1 file" ],
                                  "pair_file_2" => [ "string", "RFC 4122 UUID for pair 2 file" ],
                                  "output"      => [ "string", "name of output file, default is 'pair_file_1'_'pair_file_2'.fastq" ],
                                  "retain"      => [ "boolean", "If true retain non-overlapping sequences, default is false" ] }
              }
            },
            { 'name'        => "pair_join_demultiplex",
              'request'     => $self->cgi->url."/".$self->name."/pairjoin_demultiplex",
              'description' => "merge overlapping paired-end fastq files and demultiplex based on index file - submits AWE job",
              'example'     => [ 'curl -X POST -H "auth: auth_key" -F "pair_file_1=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" -F "pair_file_2=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" -F "index_file=cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" "'.$self->cgi->url."/".$self->name.'/pairjoin_demultiplex"',
                                 "merge overlapping paired-end fastq files then demultiplex with index file, for given ids" ],
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'        => [ 'string', "user login" ],
                  'user'      => [ 'string', "user name" ],
                  'awe_id'    => [ 'string', "url/id of awe job" ],
                  'status'    => [ 'string', "status message" ],
                  'timestamp' => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => { "pair_file_1"   => [ "string", "RFC 4122 UUID for pair 1 file" ],
                                  "pair_file_2"   => [ "string", "RFC 4122 UUID for pair 2 file" ],
                                  "index_file"    => [ "string", "RFC 4122 UUID for optional index (barcode) file" ],
                                  "barcode_count" => [ "int", "number of unique barcodes in index_file" ],
                                  "prefix"        => [ "string", "prefix for output file names, default is 'pair_file_1'_'pair_file_2'" ],
                                  "retain"        => [ "boolean", "If true retain non-overlapping sequences, default is false" ] }
              }
            }
        ]
    };
    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    
    # must have auth
    if ($self->user) {
        # upload or view
        if (scalar(@{$self->rest}) == 0) {
            if ($self->method eq 'GET') {
                $self->view_inbox();
            } elsif ($self->method eq 'POST') {
                $self->upload_file();
            }
        # inbox actions that don't make new nodes
        } elsif (($self->method eq 'GET') && (scalar(@{$self->rest}) > 1)) {
            if ($self->rest->[0] eq 'info') {
                $self->file_info($self->rest->[1]);
            } elsif ($self->rest->[0] eq 'stats') {
                $self->seq_stats($self->rest->[1]);
            }
        # inbox actions that make new nodes
        } elsif (($self->method eq 'POST') && (scalar(@{$self->rest}) > 0)) {
            if ($self->rest->[0] eq 'sff2fastq') {
                $self->sff_to_fastq();
            } elsif ($self->rest->[0] eq 'demultiplex') {
                $self->demultiplex();
            } elsif ($self->rest->[0] eq 'pairjoin') {
                $self->pair_join();
            } elsif ($self->rest->[0] eq 'pair_join_demultiplex') {
                $self->pair_join(1);
            }
        }
    }
    $self->info();
}

sub file_info {
    my ($self, $uuid) = @_;
    
    # get and validate file
    my $node = $self->node_from_id($uuid);
    
    my ($file_type, $err_msg, $file_format);
    my $file_suffix = (split(/\./, $node->{file}{name}))[-1];
    
    if (int($node->{file}{size}) == 0) {
        # zero sized file
        ($file_type, $err_msg) = ("empty file", "[error] file '".$node->{file}{name}."' is empty.");
        $file_format = "none";
    } else {
        # download first 2000 bytes of file for quick stats
        my $time = time;
        my $tempfile = $Conf::temp."/temp.".$node->{file}{name}.".".$time;
        $self->get_shock_file($uuid, $tempfile, $self->mgrast_token, "length=2000");
        ($file_type, $err_msg) = $self->verify_file_type($tempfile, $node->{file}{name});
        $file_format = $self->get_file_format($tempfile, $file_type, $file_suffix);
        unlink($tempfile);
    }
    
    # get info / update node
    my $stats_info = {
        type      => $file_type,
		suffix    => $file_suffix,
		file_type => $file_format,
		file_name => $node->{file}{name},
		file_size => $node->{file}{size},
		checksum  => $node->{file}{checksum}{md5}
    };
    my $new_attr = $node->{attributes};
    if (exists $new_attr->{stats_info}) {
        map { $new_attr->{stats_info}{$_} = $stats_info->{$_} } keys %$stats_info;
    } else {
        $new_attr->{stats_info} = $stats_info;
    }
    $self->update_shock_node($node->{id}, $new_attr, $self->mgrast_token);
    
    # return data
    $self->return_data({
        id         => 'mgu'.$self->user->_id,
        user       => $self->user->login,
        status     => $err_msg ? $err_msg : "file info completed sucessfully",
        stats_info => $stats_info,
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub seq_stats {
    my ($self, $uuid) = @_;
    
    # get and validate file
    my $node = $self->node_from_id($uuid);
    my $file_type = $self->file_type_from_node($node);
    
    # Do template replacement of MG-RAST's AWE workflow for sequence stats
    my $user_id = 'mgu'.$self->user->_id;
    my $info = {
        shock_url    => $Conf::shock_url,
        job_name     => $user_id.'_seqstats_'.$node->{id},
        file_type    => $file_type,
        user_id      => $user_id,
        clientgroups => $Conf::mgrast_inbox_clientgroups,
        seq_file_id  => $node->{id},
        seq_file     => $node->{file}{name}
    };
    my $job = $self->submit_awe_template($info, $Conf::mgrast_seq_stats_workflow);
    
    # return data
    $self->return_data({
        id        => $user_id,
        user      => $self->user->login,
        status    => "stats computation is being run on file id: ".$node->{id},
        awe_id    => $Conf::awe_url.'/job/'.$job->{id},
        timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub sff_to_fastq {
    my ($self) = @_;

    # get and validate sequence file
    my $uuid = $self->cgi->param('sff_file') || "";
    unless ($uuid) {
        $self->return_data( {"ERROR" => "this request type requires the sff_file parameter"}, 400 );
    }
    my $node = $self->node_from_id($uuid);
    
    # Do template replacement of MG-RAST's AWE workflow for sff to fastq
    my $user_id = 'mgu'.$self->user->_id;
    my $info = {
        shock_url    => $Conf::shock_url,
        job_name     => $user_id.'_sff2fastq_'.$node->{id},
        user_id      => $user_id,
        user_name    => $self->user->login,
        user_email   => $self->user->email,
        clientgroups => $Conf::mgrast_inbox_clientgroups,
        sff_file_id  => $node->{id},
        sff_file     => $node->{file}{name},
        fastq_file   => $node->{file}{name}.'.fastq'
    };
    my $job = $self->submit_awe_template($info, $Conf::mgrast_sff_to_fastq_workflow);
    
    # return data
    $self->return_data({
        id        => $user_id,
        user      => $self->user->login,
        status    => "sff to fastq is being run on file id: ".$node->{id},
        awe_id    => $Conf::awe_url.'/job/'.$job->{id},
        timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub demultiplex {
    my ($self) = @_;
    
    # get and validate files
    my $seq_file = $self->cgi->param('seq_file') || "";
    my $bar_file = $self->cgi->param('barcode_file') || "";
    unless ($seq_file && $bar_file) {
        $self->return_data( {"ERROR" => "this request type requires both the seq_file and barcode_file parameters"}, 400 );
    }
    my $seq_node = $self->node_from_id($seq_file);
    my $bar_node = $self->node_from_id($bar_file);
    my $seq_type = $self->file_type_from_node($seq_node);
    
    # download barcode file to get number and names of barcoded pieces
    my $bc_count = $self->cgi->param('barcode_count') || 0;
    if ($bc_count < 2) {
        $self->return_data( {"ERROR" => "barcode_count value must be greater than 1"}, 400 );
    }
    my $outfiles = {};
    my $bar_text = $self->get_shock_file($bar_node->{id}, undef, $self->mgrast_token);
    foreach my $line (split(/\n/, $bar_text)) {
        my ($b, $n) = split(/\t/, $line);
        my $fname = $n ? $n : $b;
        $outfiles->{$fname} = 1;
    }
    if (scalar(keys %$outfiles) != $bc_count) {
        $self->return_data( {"ERROR" => "number of unique barcodes in barcode_file does not match barcode_count"}, 404 );
    }
    my $output_text = "";
    foreach my $fname (keys %$outfiles) {
        $output_text .= qq(
        "$fname.$seq_type": {
            "host": ").$Conf::shock_url.qq(",
            "node": "-",
            "attrfile": "userattr.json"
        },);
    }
    $output_text .= qq(
    "nobarcode.).$seq_node->{file}{name}.qq(": {
        "host": ").$Conf::shock_url.qq(",
        "node": "-",
        "attrfile": "userattr.json"
    });
    
    # Do template replacement of MG-RAST's AWE workflow for demultiplex
    my $user_id = 'mgu'.$self->user->_id;
    my $info = {
        shock_url    => $Conf::shock_url,
        job_name     => $user_id.'_demultiplex_'.$node->{id},
        user_id      => $user_id,
        user_name    => $self->user->login,
        user_email   => $self->user->email,
        clientgroups => $Conf::mgrast_inbox_clientgroups,
        file_type    => $seq_type,
        seq_file_id  => $seq_node->{id},
        seq_file     => $seq_node->{file}{name},
        bar_file_id  => $bar_node->{id},
        bar_file     => $bar_node->{file}{name},
        outputs      => $output_text
    };
    my $job = $self->submit_awe_template($info, $Conf::mgrast_demultiplex_workflow);
    
    $self->return_data({
        id        => $user_id,
        user      => $self->user->login,
        status    => "demultiplex is being run on file id: ".$seq_node->{id},
        awe_id    => $Conf::awe_url.'/job/'.$job->{id},
        timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub pair_join {
    my ($self, $demultiplex) = @_;
    
    # get and validate sequence files
    my $pair1_file = $self->cgi->param('pair_file_1') || "";
    my $pair2_file = $self->cgi->param('pair_file_2') || "";
    unless ($pair1_file && $pair2_file) {
        $self->return_data( {"ERROR" => "this request type requires both the pair_file_1 and pair_file_2 parameters"}, 400 );
    }
    my $pair1_node = $self->node_from_id($pair1_file);
    my $pair2_node = $self->node_from_id($pair2_file);
    my $p1_type = $self->file_type_from_node($pair1_node);
    my $p2_type = $self->file_type_from_node($pair2_node);
    unless (($p1_type eq 'fastq') && ($p2_type eq 'fastq')) {
        $self->return_data( {"ERROR" => "both input sequence files must be fastq format"}, 400 );
    }
    
    # Do template replacement of MG-RAST's AWE workflow for demultiplex
    my $outfile = $self->cgi->param('output') || $pair1_node->{file}{name}."_".$pair2_node->{file}{name};
    my $user_id = 'mgu'.$self->user->_id;
    my $info = {
        shock_url    => $Conf::shock_url,
        job_name     => $user_id.'pair_join'.$node->{id},
        user_id      => $user_id,
        user_name    => $self->user->login,
        user_email   => $self->user->email,
        clientgroups => $Conf::mgrast_inbox_clientgroups,
        p1_file_id   => $pair1_node->{id},
        p1_file      => $pair1_node->{file}{name},
        p2_file_id   => $pair2_node->{id},
        p2_file      => $pair2_node->{file}{name},
        retain       => $self->cgi->param('retain') ? "" : "-j "
    };
    my $job = undef;
    my $status = "";
    # do pair-join with demultiplex
    if ($demultiplex) {
        $status = "pair join and demultiplex is being run on files: ".$pair1_node->{id}.", ".$pair2_node->{id}.", ".$index_node->{id};
        # validate extra options
        my $index_file = $self->cgi->param('index_file') || "";
        my $bc_count   = $self->cgi->param('barcode_count') || 0;
        my $prefix     = $self->cgi->param('prefix') || $pair1_node->{file}{name}."_".$pair2_node->{file}{name};
        unless ($index_file) {
            $self->return_data( {"ERROR" => "this request type requires the index_file parameter"}, 400 );
        }
        if ($bc_count < 2) {
            $self->return_data( {"ERROR" => "barcode_count value must be greater than 1"}, 400 );
        }
        # update template info
        my $index_node = $self->node_from_id($index_file);
        $info->{index_file} = $index_node->{file}{name};
        $info->{index_id}   = $index_node->{id};
        $info->{prefix}     = $prefix;
        $info->{outputs}    = "";
        # build outputs
        foreach my $i (1..$bc_count) {
            $info->{outputs} .= qq(
            "$prefix.$i.fastq": {
                "host": ").$Conf::shock_url.qq(",
                "node": "-",
                "attrfile": "userattr.json"
            },);
        }
        $info->{outputs} .= qq(
        "nobarcode.$prefix.join.fastq": {
            "host": ").$Conf::shock_url.qq(",
            "node": "-",
            "attrfile": "userattr.json"
        });
        $job = $self->submit_awe_template($info, $Conf::mgrast_pair_join_demultiplex_workflow);
    }
    # do pair-join only
    else {
        $status = "pair join is being run on files: ".$pair1_node->{id}.", ".$pair2_node->{id};
        $info->{out_file} = $self->cgi->param('output') || $pair1_node->{file}{name}."_".$pair2_node->{file}{name}.".fastq";
        $job = $self->submit_awe_template($info, $Conf::mgrast_pair_join_workflow);
    }
    
    $self->return_data({
        id        => $user_id,
        user      => $self->user->login,
        status    => $status,
        awe_id    => $Conf::awe_url.'/job/'.$job->{id},
        timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub view_inbox {
    my ($self) = @_;

    my $files = [];
    my $inbox = $self->get_shock_query({'type' => 'inbox', 'id' => 'mgu'.$self->user->_id}, $self->mgrast_token);
    foreach my $node (@$inbox) {
        my $info = {
            'id'        => $node->{id},
            'filename'  => $node->{file}{name},
            'filesize'  => $node->{file}{size},
            'checksum'  => $node->{file}{checksum}{md5},
            'timestamp' => $node->{created_on}
        };
        if (exists $node->{attributes}{stats_info}) {
            $info->{stats_info} = $node->{attributes}{stats_info};
        }
        push @$files, $info;
    }
    $self->return_data({
        id        => 'mgu'.$self->user->_id,
        user      => $self->user->login,
        timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime),
        files     => $files,
        url       => $self->cgi->url."/".$self->name
    });
}

sub upload_file {
    my ($self) = @_;

    my $fn = $self->cgi->param('upload');
    if ($fn) {
        if ($fn !~ /^[\w\d_\.-]+$/) {
            $self->return_data({"ERROR" => "Invalid parameters, filename allows only word, underscore, dash (-), dot (.), and number characters"}, 400);
        }
        my $fh = $self->cgi->upload('upload');
        if (defined $fh) {
            # POST upload content to shock using file handle
            # data POST, not form
            my $response = undef;
            my $io_handle = $fh->handle;
            eval {
                my $post = HTTP::Request::StreamingUpload->new(
                    POST    => $Conf::shock_url.'/node',
                    fh      => $io_handle,
                    headers => HTTP::Headers->new(
                        'Content_Type' => 'application/octet-stream',
                        'Authorization' => 'OAuth '.$self->mgrast_token
                    )
                );
                my $req = LWP::UserAgent->new->request($post);
                $response = $self->json->decode( $req->content );
            };
            if ($@ || (! ref($response))) {
                $self->return_data({"ERROR" => "Unable to connect to Shock server"}, 507);
            } elsif (exists($response->{error}) && $response->{error}) {
                $self->return_data({"ERROR" => "Unable to POST to Shock: ".$response->{error}[0]}, $response->{status});
            }
            # PUT file name to node
            my $node_id = $response->{data}{id};
            my $node = $self->update_shock_node_file_name($node_id, "".$fn, $self->mgrast_token);
            unless ($node && ($node->{id} eq $node_id)) {
                $self->return_data({"ERROR" => "storing object failed - unable to set file name"}, 507);
            }
            my $attr = {
                type  => 'inbox',
                id    => 'mgu'.$self->user->_id,
                user  => $self->user->login,
                email => $self->user->email
            };
            # PUT attributes to node
            $node = $self->update_shock_node($node_id, $attr, $self->mgrast_token);
            # return info
            if ($node && ($node->{id} eq $node_id)) {
                $self->return_data({
                    id        => 'mgu'.$self->user->_id,
                    user      => $self->user->login,
                    status    => "data received successfully",
                    timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
                });
            } else {
                $self->return_data({"ERROR" => "storing object failed - unable to update file with user info"}, 507);
            }
        } else {
            $self->return_data( {"ERROR" => "storing object failed - could not obtain filehandle"}, 507 );
        }
    } else {
        $self->return_data( {"ERROR" => "invalid parameters, requires filename and data"}, 400 );
    }
}

sub submit_awe_template {
    my ($self, $info, $template) = @_;
    
    # do template replacement
    my $tt = Template->new( ABSOLUTE => 1 );
    my $awf = '';
    $tt->process($template, $info, \$awf) || die $tt->error();
    
    # Submit job to AWE and check for successful submission
    my $job = $self->post_awe_job($awf, $self->mgrast_token, $self->mgrast_token, 1);
    unless ($job && $job->{state} && $job->{state} == "init") {
        $self->return_data( {"ERROR" => "job could not be submitted"}, 500 );
    }
    
    return $job;
}

sub node_from_id {
    my ($self, $uuid) = @_;
    my $node  = {};
    my $inbox = $self->get_shock_query({'type' => 'inbox', 'id' => 'mgu'.$self->user->_id}, $self->mgrast_token);
    foreach my $n (@$inbox) {
        if ($n->{id} eq $uuid) {
            $node = $n;
        }
    }
    unless (%$node) {
        $self->return_data( {"ERROR" => "file id '$uuid' does not exist in your inbox"}, 404 );
    }
    return $node;
}

sub file_type_from_node {
    my ($self, $node) = @_;
    unless ($node->{attributes}{stats_info} && $node->{attributes}{stats_info}{file_type}) {
        $self->return_data( {"ERROR" => "Missing file_type from stats_info, run file info request first"}, 404 );
    }
    my $file_type = $node->{attributes}{stats_info}{file_type};
    unless (($file_type eq 'fasta') || ($file_type eq 'fastq')) {
        $self->return_data( {"ERROR" => "Invalid file_type: $file_type"}, 404 );
    }
    return $file_type;
}

sub verify_file_type {
    my ($self, $tempfile, $fname) = @_;
    # Need to do the 'safe-open' trick here, file might be hard to escape in the shell
    open(P, "-|", "file", "-b", "$tempfile") || $self->return_data( {"ERROR" => "unable to verify file type/format"}, 400 );
    my $file_type = <P>;
    close(P);
    chomp $file_type;

    if ( $file_type =~ m/\S/ ) {
	    $file_type =~ s/^\s+//;   #...trim leading whitespace
	    $file_type =~ s/\s+$//;   #...trim trailing whitespace
    } else {
	    # file does not work for fastq -- craps out for lines beginning with '@'
	    # check first 4 lines for fastq like format
	    my @lines = `cat -A '$file' 2>/dev/null | head -n4`;
	    chomp @lines;
	    if ( ($lines[0] =~ /^\@/) && ($lines[0] =~ /\$$/) && ($lines[1] =~ /\$$/) &&
	         ($lines[2] =~ /^\+/) && ($lines[2] =~ /\$$/) && ($lines[3] =~ /\$$/) ) {
	        $file_type = 'ASCII text';
	    } else {
	        $file_type = 'unknown file type';
	    }
    }

    if ($file_type =~ /^ASCII/) {
	    # ignore some useless information and stuff that gets in when the file command guesses wrong
	    $file_type =~ s/, with very long lines//;
	    $file_type =~ s/C\+\+ program //;
	    $file_type =~ s/Java program //;
	    $file_type =~ s/English //;
    } else {
	    $file_type = "binary or non-ASCII file";
    }

    # now return type and error
    if ( ($file_type eq 'ASCII text') ||
         ($file_type eq 'ASCII text, with CR line terminators') ||
         ($file_type eq 'ASCII text, with CRLF line terminators') ) {
        return ($file_type, "");
    } else {
        $file_type = "ASCII text, with invalid line terminators";
    }
    return ($file_type, "[error] file '$fname' is of unsupported file type '$file_type'.");
}

sub file_format {
    my ($self, $tempfile, $file_type, $file_suffix) = @_;

    if ($file_suffix eq 'qual') {
	    return 'qual';
    }
    if (($file_type =~ /^binary/) && ($file_suffix eq 'sff')) {
	    return 'sff';
    }
    # identify fasta or fastq
    if ($file_type =~ /^ASCII/) {
	    my @chars;
	    my $old_eol = $/;
	    my $line;
	    my $i;
	    open(TMP, "<$tempfile") || $self->return_data( {"ERROR" => "unable to verify file type/format"}, 400 );
	    # ignore blank lines at beginning of file
	    while (defined($line = <TMP>) and chomp $line and $line =~ /^\s*$/) {}
	    close(TMP);
	    $/ = $old_eol;

	    if ($line =~ /^LOCUS/) {
	        return 'genbank';
	    } elsif ($line =~ /^>/) {
	        return 'fasta';
        } elsif ($line =~ /^@/) {
	        return 'fastq';
        } else {
	        return 'malformed';
	    }
    } else {
	    return 'unknown';
    }
}

1;
