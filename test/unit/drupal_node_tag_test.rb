require 'test_helper'

class DrupalNodeTagTest < ActiveSupport::TestCase

  test "tag basics" do
    node = node(:one)
    assert node.has_tag('activity:spectrometer')
    assert node.has_tag('activi*')
    assert node.normal_tags.length < node.tags.length
    assert_equal node.tagnames, node.tags.collect(&:name)
    assert Tag.find_nodes_by_type('spectrometer').to_a.include?(node)
    assert Tag.find_nodes_by_type_with_all_tags(['spectrometer']).to_a.include?(node)
    assert_not_nil Tag.follower_count('spectrometer')
    assert_not_nil Tag.followers('spectrometer')
    assert_not_nil tags(:spectrometer).weekly_tallies
    assert_not_nil Tag.subscribers([tags(:spectrometer)])
  end

  # as we eliminate legacy Drupal naming schemes, these can be removed:
  test "tag method aliases" do
    node = node(:one)
    assert_equal node.tags, node.tag
    assert_equal node.community_tags, node.drupal_node_community_tag
  end

  # Tag parenting guide, as this is complicated:

  # "spectrometry"           is a parent to  "spectrometer" and "oil-testing"
  # "aerial photography"     is a parent to  "balloon-mapping" and "kite-mapping" and "pole-mapping"
  # "multispectral-imaging"  is a parent to  "infragram" and "NDVI"

  # fixture:
  # spectrometer:
  #   parent: spectrometry

  # in unit tests:
  # 1. if a post is tagged with child tag like "balloon-mapping", 
  #   does it appear in a notes/activities/questions grid for its parent tag, like "aerial-photography"? Yes.
  #   So, application_helper's insert_extras(body) should use a model method like Tag.find_nodes_by_type
  # 2. has_tag will return parent tags, but not child tags, for now. Not used a lot. 
  # 3. create an 'aliases = true' param for some of these

  # in functional tests:
  # 1. at https://publiclab.org/tag/<parent>, do you see things tagged with the child tag? Yes.
  # 2. at https://publiclab.org/tag/<child>, do you see things tagged with parent tag? No. 

  # if 'spectrometry' has a 'parent' value of 'spectrometer'
  test "aliasing of tag specified in tag.parent" do
    node = node(:one)
    assert_equal tags(:spectrometer).parent, 'spectrometry'
    assert_equal tags(:spectrometry).parent, nil
    assert       node.has_tag('spectrometer') # this is directly true
    assert       node.has_tag('spectrometry') # this true via aliasing
    assert       node.has_tag_without_aliasing('spectrometer')
    assert_false node.has_tag_without_aliasing('spectrometry')
    assert_equal node.get_matching_tags_without_aliasing('spectrometer').length, 1
    assert_equal node.get_matching_tags_without_aliasing('spectrometry').length, 0
    assert_false Tag.find_nodes_by_type('spectrometry').to_a.include?(node)
    assert_false Tag.find_nodes_by_type_with_all_tags(['spectrometry']).to_a.include?(node)
    assert       Tag.find_nodes_by_type('spectrometer').to_a.include?(node)
    assert       Tag.find_nodes_by_type_with_all_tags(['spectrometer']).to_a.include?(node)

    # test node.add_tag, which uses has_tag
    saved, tag = node.add_tag('spectrometry', rusers(:bob))
    assert saved
    assert_not_nil tag
  end

  test "aliasing of tags which have parent matching initial tag" do
    node = node(:one)
    tag = tags(:spectrometry)
    tag.parent = "spectrometer"
    tag.save
    tag2 = tags(:spectrometer)
    tag2.parent = ""
    tag2.save
    assert       node.has_tag('spectrometer') # this is directly true
    assert_false node.has_tag('spectrometry') # should return false; <spectrometer>.parent == ""
    assert Tag.find_nodes_by_type('spectrometer').to_a.include?(node)
    assert Tag.find_nodes_by_type_with_all_tags(['spectrometer']).to_a.include?(node)
    assert Tag.find_nodes_by_type('spectrometry').to_a.include?(node)
    assert Tag.find_nodes_by_type_with_all_tags(['spectrometry']).to_a.include?(node)
  end

  test "aliasing of cross-parented tags" do
    node = node(:one)
    tag = tags(:spectrometry)
    tag.parent = "spectrometer"
    tag.save
    tag2 = tags(:spectrometer)
    tag2.parent = "spectrometry"
    tag2.save
    assert node.has_tag('spectrometer') # this is directly true
    assert node.has_tag('spectrometry') # should return true even if the node only has tag 'spectrometer'
    assert Tag.find_nodes_by_type('spectrometry').to_a.include?(node)
    assert Tag.find_nodes_by_type_with_all_tags(['spectrometry']).to_a.include?(node)
  end

  test "power tag basics" do
    assert Tag.is_powertag?('activity:spectrometer')
    node = node(:one)
    assert node.has_power_tag('activity')
    assert_equal 'spectrometer', node.power_tag('activity')
    assert_equal 'spectrometer', node.power_tag('activity')
    assert_equal ['spectrometer'], node.power_tags('activity')
    assert_equal 'String', node.power_tags('activity').first.class.to_s
    assert_equal 'DrupalNodeCommunityTag', node.power_tag_objects('activity').first.class.to_s
  end

  test "power tag based node features" do
    node = node(:one)
    assert node.response_count
    assert node.responses
    assert node.responded_to
    assert_equal false, node.has_mailing_list?
    assert_equal false, node.lat
    assert_equal false, node.lon
    assert_nil node.tagged_lat
    assert_nil node.tagged_lon
  end

  test "can't powertag with: yourself" do
    user = node(:blog).author
    tagname = "with:#{user.username}"
    assert_equal I18n.t('node.cannot_add_yourself_coauthor'), node(:blog).can_tag(tagname, user, true)
    assert_false node(:blog).can_tag(tagname, user)
  end

  test "can powertag with: another user" do
    jeff = node(:blog).author
    bob = rusers(:bob)
    assert bob.username != jeff.username
    assert node(:blog).can_tag("with:#{bob.username}", jeff)
  end

  test "can't tag with: a nonexistent user" do
    user = rusers(:bob)
    tagname = "with:steven"
    assert_equal I18n.t('node.cannot_find_username'), node(:blog).can_tag(tagname, user, true)
    assert_false node(:blog).can_tag(tagname, user)
  end

  test "can't powertag with: if you're not author" do
    bob = rusers(:bob)
    jeff = rusers(:jeff)
    node = Node.new({
      uid: jeff.id,
      type: 'note',
      title: 'My research note'
    })
    tagname = "with:#{jeff.username}"
    assert_equal I18n.t('node.only_author_use_powertag'), node.can_tag(tagname, bob, true)
    assert_false node.can_tag(tagname, bob)
  end

  test "can rsvp yourself" do
    user = node(:blog).author
    tagname = "rsvp:#{user.username}"
    assert node(:blog).can_tag(tagname, user)
    assert_true node(:blog).can_tag(tagname, user)
  end

  test "can't rsvp someone else" do
    user = rusers(:bob)
    jeff = rusers(:jeff)
    node = Node.new({
      uid: user.id,
      type: 'note',
      title: 'My research note'
    })
    tagname = "rsvp:#{jeff.username}"
    assert_not_equal true,  node.can_tag(tagname, user, true) # return errors with optional 3rd parameter
    assert_not_equal false, node.can_tag(tagname, user, true)
    assert_equal I18n.t('node.only_RSVP_for_yourself'), node.can_tag(tagname, user, true)
    assert_false node.can_tag(tagname, user) # default is true/false
  end

  test "only admins can lock pages" do
    assert_false node(:blog).can_tag('locked', rusers(:bob))
    assert node(:blog).can_tag('locked', rusers(:admin))
    assert_equal I18n.t('node.only_admins_can_lock'), node(:blog).can_tag('locked', rusers(:bob), true)
  end

end
