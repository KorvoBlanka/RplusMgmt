package RplusMgmt::Controller::API::Realty;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark::Manager;

use Rplus::DB;
use Rose::DB::Object::QueryBuilder qw(build_where_clause);

use Rplus::Util::Query;
use Rplus::Util::Realty;

use JSON;

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'realty'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $q = $self->param('q');
    my $state_code = $self->param('state');
    my $offer_type_code = $self->param('offer_type');
    my $agent_id = $self->param('agent');
    my $sort_by = $self->param('sort');
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 50;

    my $res = {
        count => 0,
        list => [],
        page => $page,
    };

    my $ts_query_text;
    my @query = Rplus::Util::Query->parse($q, \$ts_query_text);
    if ($state_code && $state_code ne 'any') { push @query, state_code => $state_code } else { push @query, '!state_code' => 'deleted' };   
    if ($offer_type_code && $offer_type_code ne 'any') { push @query, offer_type_code => $offer_type_code } else {};
    if ($agent_id && $agent_id ne 'any') {
        if ($agent_id eq 'nobody') {
            push @query, agent_id => undef
        } elsif ($agent_id eq 'all') {
            push @query, '!agent_id' => undef
        } else {
            push @query, agent_id => $agent_id
        }
    } else {};

    my (@sort_by, @with_objects);
    if  ($sort_by && $sort_by =~ /^(\w+)(\.\w+)? (asc|desc)$/) {
      push @with_objects, $1 if $1 && $2;
      push @sort_by, $sort_by;
    }

    # Full Text Search
    if ($ts_query_text) {
        my $dbh = Rplus::DB->new_or_cached->dbh;

        # Try to recognize landmarks
        my (@landmarks, @hl);
        {
            my $sth = $dbh->prepare("
                SELECT id, name, ts_headline('russian', '".($ts_query_text =~ s/'/''/gr)."', plainto_tsquery('russian', keyword), 'StartSel=|,StopSel=|') hl
                FROM (
                    SELECT id, name, regexp_split_to_table(keywords, ',') keyword
                    FROM landmarks L
                    WHERE L.delete_date IS NULL
                ) SS
                WHERE to_tsvector('russian', ?) @@ plainto_tsquery('russian', keyword)
                ORDER BY length(keyword) DESC
            ");
            $sth->execute($ts_query_text);
            while (my $row = $sth->fetchrow_hashref) {
                push @landmarks, $row->{'id'};
                my ($s, $p) = (0, 0);
                while ((my $i = index($row->{'hl'}, '|', $s)) != -1) { push @hl, $i - $p; $s = $i + 1; $p++; }
            }
        }
        if (@landmarks) {
            #push @query, \("(SELECT count(L.id) FROM landmarks L WHERE L.id IN (".join(',',@landmarks).") AND L.geodata::geography && t1.geocoords AND L.delete_date IS NULL) > 0");
            push @query, \("t1.landmarks && '{".join(',', @landmarks)."}'");
            my %hl = @hl;
            while (my ($s, $e) = each %hl) {
                substr($ts_query_text, $s, $e - $s, ' ' x ($e - $s));
            }
        }

        my $ts_query = join(' | ', grep { $_ } split(/\W/, lc($ts_query_text)));
        if ($ts_query) {
            $ts_query =~ s/'/''/g;
            push @query, \("t1.fts @@ to_tsquery('russian', '$ts_query')");

            my $dbh = Rplus::DB->new_or_cached->dbh;
            my ($where, $bind) = build_where_clause(
                dbh => $dbh,
                tables => ['realty'],
                columns => {realty => [Rplus::Model::Realty->meta->column_names]},
                query => \@query,
                query_is_sql => 1,
            );
            my $sql = qq{
              SELECT round(ts_rank(t1.fts, to_tsquery('russian', '$ts_query'))::numeric, 5) rank, count(t1.id) count
              FROM realty t1
              WHERE $where
              GROUP BY round(ts_rank(t1.fts, to_tsquery('russian', '$ts_query'))::numeric, 5)
              ORDER BY rank DESC
              LIMIT 2
            };
            my $sth = $dbh->prepare($sql);
            $sth->execute(@$bind);
            my %ranks;
            while (my $row = $sth->fetchrow_hashref) {
                #next unless $row->{'rank'} > 0;
                $ranks{$row->{'rank'}} = $row->{'count'};
                $res->{'count'} += $row->{'count'};
            }

            push @query, \("round(ts_rank(t1.fts, to_tsquery('russian', '$ts_query'))::numeric, 5) IN (".join(',', sort keys %ranks).")") if %ranks;
            unshift @sort_by, "ts_rank(t1.fts, to_tsquery('russian', '$ts_query')) DESC";
        } else {
            $res->{'count'} = Rplus::Model::Realty::Manager->get_objects_count(query => \@query);
        }
    } else {
        $res->{'count'} = Rplus::Model::Realty::Manager->get_objects_count(query => \@query);
    }

    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
        select => ['realty.*', map { 'address_object.'.$_ } ('id', 'name', 'short_type', 'expanded_name', 'metadata')],
        query => \@query,
        sort_by => \@sort_by,
        page => $page,
        per_page => $per_page,
        with_objects => ['address_object', @with_objects],
    );
    while (my $realty = $realty_iter->next) {
        my $metadata = decode_json($realty->metadata);
        push @{$res->{'list'}}, {
            address_object => $realty->address_object_id ? {
                id => $realty->address_object->id,
                name => $realty->address_object->name,
                short_type => $realty->address_object->short_type,
                expanded_name => $realty->address_object->expanded_name,
                addr_parts => decode_json($realty->address_object->metadata)->{'addr_parts'},
            } : undef,

            (map { $_ => scalar $realty->$_ } grep { !/^(?:metadata)|(?:geocoords)|(?:fts)|(?:landmarks)$/ } $realty->meta->column_names)
        };
    }

    $self->render(json => $res);
}

sub get {
    my $self = shift;

    my $id = $self->param('id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id], with_objects => ['address_object'])->[0];
    return $self->render_not_found unless $realty;

    # TODO: Access Control

    my $metadata = decode_json($realty->metadata);
    my $res = {
        address_object => $realty->address_object_id ? {
            id => $realty->address_object->id,
            name => $realty->address_object->name,
            short_type => $realty->address_object->short_type,
            expanded_name => $realty->address_object->expanded_name,
            addr_parts => decode_json($realty->address_object->metadata)->{'addr_parts'},
        } : undef,

        sublandmarks => @{$realty->landmarks} ? [
            map { {id => $_->id, name => $_->name} } @{Rplus::Model::Landmark::Manager->get_objects(
                select => 'id, name',
                query => [id => [@{$realty->landmarks}, $realty->sublandmark_id || ()], type => 'sublandmark', delete_date => undef],
                sort_by => 'name'
            )}
        ] : [],

        (map { $_ => scalar $realty->$_ } grep { !/^(?:metadata)|(?:geocoords)|(?:fts)|(?:landmarks)$/ } $realty->meta->column_names)
    };

    return $self->render(json => $res);
}

sub create {
    my $self = shift;

    my $x = Rplus::DB->new_or_cached->dbh->selectrow_arrayref("SELECT nextval('realty_id_seq')");

    $self->render(json => {id => $x->[0]});
}

sub save {
    my $self = shift;

    my $id = $self->param('id');
    my %data;
    for my $p ($self->param) {
        if ($p =~ /\[\]$/) {
            $data{$p =~ s/\[\]$//r} = [$self->param($p)];
        } else {
            $data{$p} = $self->param($p) || undef;
            if ($p =~ /ˆsquare_/ || $p=~ /_price$/) {
                $data{$p} =~ s/,/./ if $data{$p};
            }
        }
    }

    return $self->render(json => {status => 'failed', error_msg => 'No id specified'}) unless $id;

    # Поиск похожих вариантов
    my $similar_realty_id = Rplus::Util::Realty->find_similar(%data, state_code => ['raw', 'work', 'suspended']);
    my $similar_realty = Rplus::Model::Realty->new(id => $similar_realty_id)->load(with => ['address_object']) if $similar_realty_id;

    my $realty = Rplus::Model::Realty->new(id => $id)->load(speculative => 1);
    # TODO: Access control
    $realty = Rplus::Model::Realty->new(id => $id) unless $realty;

    for my $f (@{$realty->meta->column_names}) {
        next if $f eq 'id';
        next if $f =~ /_date$/;
        next if $f eq 'creator_id';
        next if $f eq 'price';
        next if $f eq 'geocoords';
        next if $f eq 'landmarks';
        next if $f eq 'fts';
        next if $f eq 'metadata';

        if ($f eq 'export_media' && exists $data{$f}) {
            my @export_media;
            if (ref($data{$f}) eq 'ARRAY' && @{$data{$f}}) {
                @export_media = map { $_->id } @{Rplus::Model::Media::Manager->get_objects(query => [id => $data{$f}, type => ['any', 'export'], delete_date => undef])};
            }
            $realty->export_media(\@export_media);
        } elsif ($f eq 'tags') {
        } elsif ($f eq 'seller_phones' && exists $data{$f}) {
            my @seller_phones;
            if (ref($data{$f}) eq 'ARRAY') {
                @seller_phones = grep { /^\d{10}$/ } @{$data{$f}};
            }
            $realty->seller_phones(\@seller_phones);
        } elsif (exists $data{$f}) {
            $realty->$f($data{$f});
        }
    }

    $realty->save($realty->id ? (changes_only => 1) : (insert => 1));
    Rplus::Model::Realty::Manager->update_objects(set => {change_date => \"now()"}, where => [id => $realty->id]);
    $realty->load;

    my $metadata = decode_json($realty->metadata);
    my $res = {
        address_object => $realty->address_object_id ? {
            id => $realty->address_object->id,
            name => $realty->address_object->name,
            short_type => $realty->address_object->short_type,
            expanded_name => $realty->address_object->expanded_name,
            addr_parts => decode_json($realty->address_object->metadata)->{'addr_parts'},
        } : undef,

        sublandmarks => @{$realty->landmarks} ? [
            map { {id => $_->id, name => $_->name} } @{Rplus::Model::Landmark::Manager->get_objects(
                select => 'id, name',
                query => [id => [@{$realty->landmarks}, $realty->sublandmark_id || ()], type => 'sublandmark', delete_date => undef],
                sort_by => 'name'
            )}
        ] : [],

        (map { $_ => scalar $realty->$_ } grep { !/^(?:metadata)|(?:geocoords)|(?:fts)$/ } $realty->meta->column_names),

        ($similar_realty ? (similar => {
            id => $similar_realty->id,
            type_code => $similar_realty->type_code,
            address_object => $similar_realty->address_object_id ? {
                id => $similar_realty->address_object->id,
                name => $similar_realty->address_object->name,
                short_type => $similar_realty->address_object->short_type,
                expanded_name => $similar_realty->address_object->expanded_name,
            } : undef,
            house_num => $similar_realty->house_num,
        }) : ())
    };

    $self->render(json => {status => 'success', data => $res});
}

1;
