package RplusMgmt::Controller::API::Photo;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Rplus::Util::Image;

sub list {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'read');

    my $realty_id = $self->param('realty_id');
    my $realty = Rplus::Model::Realty::Manager->get_objects(select => 'id, agent_id', query => [id => $realty_id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => read => $realty->agent_id);

    my $res = {
        count => 0,
        list => [],
    };

    my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty_id, delete_date => undef], sort_by => 'id');
    while (my $photo = $photo_iter->next) {
      my $url = '';
      if ($photo->filename !~ /^http/) {
          $url = $self->config->{storage}->{url} . '/photos/';
      }
      my $x = {
        id => $photo->id,
        photo_url => $url . $photo->filename,
        thumbnail_url => $url . $photo->thumbnail_filename,
        is_main => $photo->is_main ? \1 : \0,
      };
      push @{$res->{list}}, $x;
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub upload {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');
    return $self->render(json => {error => 'Limit is exceeded'}, status => 500) if $self->req->is_limit_exceeded;

    my $realty_id = $self->param('realty_id');
    my $realty = Rplus::Model::Realty::Manager->get_objects(select => 'id, agent_id', query => [id => $realty_id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);

    if (my $file = $self->param('files[]')) {

      my $url = $self->config->{storage}->{url} . '/photos';
      my $storage_path = $self->config->{storage}->{path};
      my $crop = 0;
      my $photo;
      eval {
        $photo = Rplus::Util::Image::load_image($realty_id, $file, $storage_path, $crop);
      } or do {
        return $self->render(json => {error => $@}, status => 500);
      };

      # Update realty change_date
      Rplus::Model::Realty::Manager->update_objects(
        set => {change_date => \'now()'},
        where => [id => $realty_id],
      );

      return $self->render(json => {status => 'success', id => $photo->id, realty_id => $realty_id, thumbnail_url => $url . '/' . $photo->thumbnail_filename,});
    }

    return $self->render(json => {error => 'Bad Request'}, status => 400);
}

sub update {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $id = $self->param('id');

    my $photo = Rplus::Model::Photo::Manager->get_objects(query => [id => $id, delete_date => undef, 'realty.delete_date' => undef], require_objects => ['realty'])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $photo;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $photo->realty->agent_id);

    # Validation
    $self->validation->required('is_main')->in(qw/0 1 true false/);

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {is_main => 'Invalid value'} if $self->validation->has_error('is_main');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Remove old "is_main" photo
    my $num_rows_updated = Rplus::Model::Photo::Manager->update_objects(
        set => {is_main => 0},
        where => [realty_id => $photo->realty_id, is_main => 1], # delete_date is not used
    );

    # Prepare data
    my $is_main = $self->param_b('is_main');

    # Save
    $photo->is_main($is_main);

    $photo->save;

    return $self->render(json => {status => 'success'});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $id = $self->param('id');

    my $photo = Rplus::Model::Photo::Manager->get_objects(query => [id => $id, delete_date => undef], require_objects => ['realty'])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $photo;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $photo->realty->agent_id);

    Rplus::Model::Photo::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $photo->id],
    );

    Rplus::Model::Realty::Manager->update_objects(
        set => {change_date => \'now()'},
        where => [id => $photo->realty_id],
    );

    $self->render(json => {status => 'success'});
}

1;
