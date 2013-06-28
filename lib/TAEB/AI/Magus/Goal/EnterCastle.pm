package TAEB::AI::Magus::Goal::EnterCastle;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->current_level->is_castle }

1;

