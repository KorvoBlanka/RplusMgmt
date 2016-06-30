package RplusMgmt::Controller::API::Statistics;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::RealtyColorTag;
use Rplus::Model::RealtyColorTag::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Model::DictTaskType;
use Rplus::Model::DictTaskType::Manager;

use Rplus::Util::PhoneNum;
use Rplus::Util::Query;
use Rplus::Util::Realty;
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::Task;
use Rplus::Util::Geo;


use File::Path qw(make_path);
use POSIX qw(strftime);

use JSON;
use Mojo::Collection;
use Time::Piece;


no warnings 'experimental::smartmatch';

sub get_price_data {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'read');

    # Input validation

    # Input params
    my $q = $self->param_n('q');
    my $offer_type_code = $self->param('offer_type_code') || 'any';
    my $rent_type = $self->param('rent_type') || 'any';

    my $from_date = $self->param('from_date');
    my $to_date = $self->param('to_date');

    my $object_count = $self->param("object_count") || 10000;

    my $rq_id = $self->param("rq_id") || 42;
    my $acc_id = $self->session('account')->{id};


    # "where" query
    my @query;
    my $near;
    {
        if ($q =~ s/(рядом )(.+)/ /i) {
            $near = $2;
        }

        if ($from_date) {
          push @query, add_date => {gt => $from_date};
        }

        if ($to_date) {
          push @query, add_date => {le => $to_date};
        }

        if ($offer_type_code eq 'rent' && $rent_type ne 'any') {
            push @query, rent_type => $rent_type;
        }
    }

    # Recognize phone numbers from query
    my @owner_phones;
    if ($q) {
        for my $x (split /[ .,]/, $q) {
            if ($x =~ /^\s*[0-9-]{6,}\s*$/) {
                if (my $phone_num = $self->parse_phone_num($x)) {
                    push @owner_phones, $phone_num;
                    $q =~ s/$x//;
                }
            }
        }
        push @query, \("t1.owner_phones && '{".join(',', map { '"'.$_.'"' } @owner_phones)."}'") if @owner_phones;
    }

    push @query, or => [account_id => undef, account_id => $acc_id];
    push @query, \("NOT hidden_for && '{".$acc_id."}'");

    # Parse query
    push @query, Rplus::Util::Query::parse($q, $self);

    if ($near) {
        my $points = get_near_filter($near);

        my $max_points = 100;
        if (scalar @{$points}) {
            my @near_query = ();
            foreach (@{$points}) {
                if ((scalar @near_query) == $max_points) {last};
                push @near_query, \("postgis.st_distance(t1.geocoords, postgis.ST_GeographyFromText('SRID=4326;POINT(" . $_->{lon} . " " . $_->{lat} . ")'), true) < 500");
            }

            push @query, or => \@near_query;
        }
    }


    my $res = {
      list => []
    };

    # Fetch realty objects
    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator (
        select => ['realty.add_date', 'realty.price'],
        query => [
            @query,
            delete_date => undef,
        ],
        page => 1,
        per_page => $object_count,
    );

    while (my $realty = $realty_iter->next) {
        my $x = {
            add_date => $realty->add_date,
            cost => $realty->price,
        };
        push @{$res->{list}}, $x;
    }

    return $self->render(json => $res);
}

sub get_agent_objects_data {
  my $self = shift;

  my $agent_id = $self->param('agent_id');
  my $offer_type_code = $self->param('offer_type_code') || 'any';

  my $res = {
    list => []
  };

  for my $x (@{Rplus::Model::RealtyState::Manager->get_objects(sort_by => 'sort_idx')}) {
    my $state_count = Rplus::Model::Realty::Manager->get_objects_count (
        query => [agent_id => $agent_id, state_code => $x->code, offer_type_code => $offer_type_code, delete_date => undef,],
    );
    my $x = {
        state_code => $x->name,
        count => $state_count,
    };
    push @{$res->{list}}, $x;
  }

  return $self->render(json => $res);
}

sub get_agent_tasks_data {
  my $self = shift;

  my $agent_id = $self->param('agent_id');

  my $from_date = $self->param('from_date');
  my $to_date = $self->param('to_date');

  my @assigned_query;
  my @done_query;

  if ($from_date) {
    push @assigned_query, start_date => {gt => $from_date};

    push @done_query, start_date => {gt => $from_date};
  }

  if ($to_date) {
    push @assigned_query, start_date => {le => $to_date};

    push @done_query, start_date => {le => $to_date};
    push @done_query, completion_date => {le => $to_date};
  } else {
    push @done_query, status => 'done';
  }

  my $res = {
    list => []
  };

  for my $x (@{Rplus::Model::DictTaskType::Manager->get_objects(query => [delete_date => undef], sort_by => 'id')}) {

    my $assigned_count = Rplus::Model::Task::Manager->get_objects_count (
      query => [
        @assigned_query,
        task_type_id => $x->id,
        assigned_user_id => $agent_id,
        delete_date => undef,
      ],
    );

    my $done_count = Rplus::Model::Task::Manager->get_objects_count (
      query => [
        @done_query,
        task_type_id => $x->id,
        assigned_user_id => $agent_id,
        delete_date => undef,
      ],
    );

    my $x = {
        task_name => $x->name,
        assigned_count => $assigned_count,
        done_count => $done_count,
    };

    push @{$res->{list}}, $x;
  }

  return $self->render(json => $res);
}

1;
