#!/usr/bin/env ruby -KU

require 'rubygems'

# we're manually including the wowr library, but otherwise we'd use this
#gem 'wowr', '=0.5.1'

require 'pp'      # pretty-prints ruby objects
require 'sequel'  # ruby sql library
require 'wowr'    # the wow armory library
require 'logger'  # allows logging of sql commands


# This is me monkey-patching a new method -- FullItem#gem_type -- onto Wowr.
# This is because there was a name conflict with Ruby's Object#type method
# and Wowr's Wowr::FullItem#type.
module Wowr
  module Classes
    class FullItem	
      def gem_type
        @info.type
      end
    end
  end
end


# This class holds the code required to put a single character in the DB.
class WoWDB

  # Creates a new instance of a WoW character and connects to the DB.
  def initialize(char_name, char_realm, db = nil)

    # each instance of a WoWDB object represents a single character
    @api = Wowr::API.new( :character_name => char_name,
    :realm => char_realm,
    :caching => false )

    # pull down the character data structure
    @char_data = @api.get_character

    # set up database connection
    @db = db || Sequel.sqlite 

    # this is what I wanted to use, but I'm had compatability issues with sqlite vs postgresql vs mysql
    #@db = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://development.db')

    # this logger will record all SQL queries to stdout
    #@db.loggers << Logger.new($stdout)

    # prints the entire character data structure
    #pp @char_data if $DEBUG
  end

  # Static method that returns a 2D array of all of the character/realm pairs in the DB
  def self.character_list(db)
    ret = []
    
    db.fetch("SELECT c.name, r.name as realm from Character c, Realm r where r.reid = c.Realm_reid;") do |row|
      ret << [row[:name], row[:realm]]
    end
    
    return ret
  end
  
  # Static method that returns a hash of character data
  def self.character_sheet(name, realm, db)
    return db.fetch("SELECT c.name, r.name as realm, c.class, c.mspec, g.name as guild from Character c, Realm r, Guild g where r.reid = c.Realm_reid and c.Guild_gid = g.gid;").first
  end

  # Static method that returns an array of item information for every item for a particular character
  def self.item_list(name, realm, db)
    ret = []
    
    db.fetch("SELECT i.name as item, i.id, i.ilvl, m.name as monster, r.name as raid, g.name as gem, g.geid, i.Enchant_eid as eid from Item i, Character_has_Item ci, Character c, Realm re, Monster m, Monster_has_Item mi, Raid r, Gem g where i.iid = ci.Item_iid and ci.Character_cid = c.cid and re.reid = c.Realm_reid and i.id = mi.Item_iid and mi.Monster_mid = m.mid and r.rid = m.Raid_rid and g.Item_iid = i.id and re.name='#{realm}' and c.name = '#{name}';") do |row|
      ret << row
    end
    
    return ret
  end
  
  # Static method that returns an array of hashes of character info for a guild
  def self.guild_listing(name, realm, db)
    return db.fetch("SELECT c.name from Character c, Realm r, Guild g where r.reid = c.Realm_reid and c.Guild_gid = g.gid and g.name='#{name}' and r.name='#{realm}';").all
  end

  # Executes the create database SQL code.
  # This is safe to run more than once because of the "create table if not exists" syntax.
  def create_database

    @db.execute("create table if not exists 'Realm' (
    'reid' integer primary key autoincrement,
    'name' varchar(20) not NULL);")

    @db.execute("create table if not exists 'Guild' (
    'gid' integer primary key autoincrement,
    'name' varchar(24) NULL ,
    'Realm_reid' int not NULL ,
    constraint 'fk_Guild_Realm1'
    foreign key ('Realm_reid')
    references 'Realm' ('reid')
    );")

    @db.execute("create table if not exists 'Character' (
    'cid' integer primary key autoincrement,
    'Guild_gid' int not NULL ,
    'name' varchar(12) not NULL ,
    'Realm_reid' int not NULL ,
    'class' varchar(12) not NULL ,
    'mspec' char(10) not NULL ,
    'sspec' char(10) NULL ,
    constraint 'fk_Character_Guild'
    foreign key ('Guild_gid')
    references 'Guild' ('gid'),
    constraint 'fk_Character_Realm1'
    foreign key ('Realm_reid')
    references 'Realm' ('reid')
    );")

    @db.execute("create table if not exists 'Enchant' (
    'eid' int not NULL,
    'name' varchar(150) not NULL ,
    primary key ('eid') );")

    @db.execute("create table if not exists 'Item' (
    'iid' integer primary key autoincrement,
    'Enchant_eid' int ,
    'name' varchar(150) not NULL ,
    'ilvl' int not NULL ,
    'id' int not NULL ,
    constraint 'fk_Item_Enchant1'
    foreign key ('Enchant_eid')
    references 'Enchant' ('eid')
    );")

    @db.execute("create table if not exists 'Raid' (
    'rid' integer primary key autoincrement,
    'name' varchar(45) not NULL ,
    'heroic' char(1) not NULL);")

    @db.execute("create table if not exists 'Monster' (
    'mid' integer primary key autoincrement,
    'Raid_rid' int not NULL ,
    'name' varchar(150) not NULL ,
    constraint 'fk_Monster_Raid1'
    foreign key ('Raid_rid')
    references 'Raid' ('rid')
    );")

    @db.execute("create table if not exists 'Gem' (
    'geid' int not NULL,
    'Item_iid' int not NULL ,
    'name' varchar(150) not NULL ,
    'color' varchar(20) not NULL ,
    'quality' varchar(20) not NULL ,
    primary key ('geid','Item_iid') ,
    constraint 'fk_Gem_Item1'
    foreign key ('Item_iid')
    references 'Item' ('iid')
    );")
    
    @db.execute("create table if not exists 'Character_has_Item' (
      'Character_cid' int not NULL ,
      'Item_iid' int not NULL ,
      primary key ('Character_cid', 'Item_iid') ,
      constraint 'fk_Character_has_Item_Character1'
        foreign key ('Character_cid')
        references 'Character' ('cid'),
      constraint 'fk_Character_has_Item_Item1'
        foreign key ('Item_iid')
        references 'Item' ('iid')
    );")

    @db.execute("create table if not exists 'Monster_has_Item' (
    'Monster_mid' int not NULL ,
    'Item_iid' int not NULL ,
    primary key ('Monster_mid', 'Item_iid') ,
    constraint 'fk_Monster_has_Item_Monster1'
    foreign key ('Monster_mid')
    references 'Monster' ('mid'),
    constraint 'fk_Monster_has_Item_Item1'
    foreign key ('Item_iid')
    references 'Item' ('iid')
    );")

  end


  # Runs an abitrary SQL command.
  # TODO: Remove me?
  def run_sql(sql)
    @db.execute(sql)
  end


  # This method generates AND EXECUTES the SQL code to insert the character into the DB.
  # It also returns the SQL code it generates as a string.
  def generate_insert_statements!
    return insert_into_Realm + "\n" + insert_into_Guild + "\n" +  insert_into_Character + "\n" +  insert_into_Item
  end


  # Generates and executes code to insert the realm into the DB.
  # Will not execute anything if the realm already exists.
  # Should be executed before the other insert_into_foo() methods.
  def insert_into_Realm
    # the name of the realm to add
    name = @char_data.realm.sub("'","\\'")

    # look to see if the realm is already in the DB
    if @db.fetch("select reid from Realm where name='#{name}'").first.nil?

      # generate the SQL query
      sql = "-- inserting #{name}\nINSERT INTO Realm (name) VALUES ('#{name}');\n"

      # run it
      @db.execute(sql)

      # return it as a string
      return sql
    else
      # just return a comment
      return "-- Realm #{name} is in the DB, skipping...\n"
    end
  end


  # Generates and executes code to insert the guild into the DB.
  # Will not execute anything if the guild already exists on this realm.
  # Should be executed after insert_into_realm().
  def insert_into_Guild
    # the name of the guild to add
    name = @char_data.guild.sub("'","\\'")

    # the id of the realm the guild is on
    realm_reid = @db.fetch("select reid from Realm where name='#{@char_data.realm.sub("'","\\'")}'").first[:reid]

    # look to see if the guild is already in the DB
    if @db.fetch("select gid from Guild where name='#{name}' and Realm_reid=#{realm_reid}").first.nil?

      # generate the SQL query
      sql = "-- inserting #{name}\nINSERT INTO Guild (name, Realm_reid) VALUES ('#{name}', #{realm_reid});\n"

      # run it
      @db.execute(sql)

      # return it as a string
      return sql
    else
      # just return a comment
      return "-- Guild #{name} is in the DB, skipping...\n"
    end
  end


  # Generates and executes code to insert the character into the DB.
  # Will not execute anything if the character already exists on this realm.
  # Should be executed after insert_into_guild().
  ##
  # TODO: Eventually support UPDATE calls. Probably beyond the scope of the project for now.
  # TODO: Figure out where the api stores secondary spec.
  def insert_into_Character
    name = @char_data.name
    realm_reid = @db.fetch("select reid from Realm where name='#{@char_data.realm.sub("'","\\'")}'").first[:reid]

    # look to see if the character is already in the DB
    if @db.fetch("select cid from Character where name='#{name}' and Realm_reid=#{realm_reid}").first.nil?

      guild_gid = @db.fetch("select gid from Guild where name='#{@char_data.guild.sub("'","\\'")}' and Realm_reid=#{realm_reid}").first[:gid]
      klass = @char_data.klass
      mspec = @char_data.talent_spec.trees[1..-1].join("/")

      # FIXME: hacky shortcut
      sspec = mspec

      # generate the SQL query
      sql = "-- inserting #{name}\nINSERT INTO Character (Guild_gid, name, Realm_reid, class, mspec, sspec) VALUES (#{guild_gid}, '#{name}', #{realm_reid}, '#{klass}', '#{mspec}', '#{sspec}');"

      # run it
      @db.execute(sql)

      # return it as a string
      return sql
    else
      # just return a comment
      return "-- Guild #{name} is in the DB, skipping...\n"
    end
  end


  # Generates and executes code to insert each item into the DB.
  # Does NOT check to see if data already exists in the DB.
  # Should be executed after insert_into_character().
  ##
  # TODO: What implications does not checking for existing data have? Duplicate key errors?
  def insert_into_Item
    # this array will contain the SQL statements for each item
    ret = []

    @char_data.items.each do |equipped|
      item = @api.get_item(equipped.id)

      enchant_eid = equipped.permanent_enchant
      name = item.name.sub("'","\\'")
      ilvl = item.level
      id = equipped.id

      # while the api uses 0 for no enchant, the schema uses NULL
      enchant_eid = "NULL" if enchant_eid.zero?


      sql = "\n-- inserting #{name}\nINSERT INTO Item (Enchant_eid, name, ilvl, id) VALUES (#{enchant_eid}, '#{name}', #{ilvl}, #{id});"
      @db.execute(sql)
      ret << sql
      
      cid = @db.fetch("SELECT c.cid from Character c, Realm r where c.name='#{@char_data.name}' and r.name='#{@char_data.realm.sub("'","\\'")}';").first[:cid]
      iid = @db.fetch("SELECT i.iid from Character c, Item i where c.name='#{@char_data.name}' and i.id=#{id};").first[:iid]
      
      sql = "\nINSERT INTO Character_has_Item (Character_cid, Item_iid) VALUES (#{cid}, #{iid});"
      @db.execute(sql)
      ret << sql
      

      # generate insert statements for the enchant if there is one
      ret << insert_into_Enchant(enchant_eid) if enchant_eid != "NULL"

      # generate insert statements for each gem in the item
      equipped.gems.each do |geid|
        next if geid.nil?
        #iid = @db.fetch("select iid from Item where name='#{name}' and Enchant_eid=#{enchant_eid}").first[:iid]
        ret << insert_into_Gem(geid, id)
      end
      
      # generate insert statements for the item source
      ret << insert_into_Raid(id)
      
    end

    return ret.join("\n")
  end


  private
  # Generates and executes code to insert an enchant into the DB.
  # Will not execute anything if the enchant already exists in the DB.
  # Private method, should only be executed by insert_into_item().
  ##
  # TODO: Figure out how to get the enchant name using the Wowr API.
  def insert_into_Enchant(eid)

    return nil if eid.zero?

    # FIXME: there doesn't appear to be a way to pull the enchant name from Wowr :(
    name = eid.to_s
    #name = @api.get_item(eid).name.sub("'","\\'")

    # look to see if the enchant is already in the DB
    if @db.fetch("select eid from Enchant where eid=#{eid}").first.nil?

      # generate the SQL query
      sql = "INSERT INTO Enchant (eid, name) VALUES (#{eid}, '#{name}');"

      # run it
      @db.execute(sql)

      # return it as a string
      return sql
    else
      # just return a comment
      return "-- Enchant #{eid} is in the DB, skipping...\n"
    end
  end


  private
  # Generates and executes code to insert a gem into the DB.
  # Will not execute anything if the gem already exists on a given item in the DB.
  # Private method, should only be executed by insert_into_item().
  def insert_into_Gem(geid, iid)

    # look to see if the gem is already in the DB
    if @db.fetch("select geid from Gem where geid=#{geid} and Item_iid=#{iid}").first.nil?

      gem_info = @api.get_item(geid)

      name = gem_info.name.sub("'","\\'")
      color = gem_info.gem_type
      quality = gem_info.quality

      # generate the SQL query
      sql = "INSERT INTO Gem (geid, Item_iid, name, color, quality) VALUES (#{geid}, #{iid}, '#{name}', '#{color}', #{quality});"

      # run it
      @db.execute(sql)

      # return it as a string
      return sql
    else
      # just return a comment
      return "-- Gem #{geid} in item #{iid} is in the DB, skipping...\n"
    end
  end

  private
  # Generates and executes code to insert an item's source into the DB.
  # Will not execute anything if the item already exists in the DB.
  # Private method, should only be executed by insert_into_item().
  def insert_into_Raid(iid)

    # look to see if the item is already in the DB
    if @db.fetch("select iid from Item where iid=#{iid}").first.nil?

      # the string of SQL queries that will be returned
      ret = ''

      item_info = @api.get_item(iid)
      source = item_info.item_source

      raid_name = source.area_name.to_s.sub("'","\\'")
      heroic = source.difficulty
      raid_rid = nil

      # check to see if the raid needs to be added to the DB
      if (raid = @db.fetch("select rid from Raid where name='#{raid_name}' and heroic='#{heroic}'").first).nil?
        # generate the SQL query to insert the raid and run it
        sql = "INSERT INTO Raid (name, heroic) VALUES ('#{raid_name}', '#{heroic}');\n"
        ret << sql
        @db.execute(sql)
        raid_rid = @db.fetch("select rid from Raid where name='#{raid_name}' and heroic='#{heroic}'").first[:rid]
      else
        # the raid exists, pull out the raid_rid from the raid data we saved above
        ret << "-- Raid #{raid_rid} is in the DB, skipping...\n"
        raid_rid = raid[:rid]
      end

      monster_name = source.creature_name
      monster_name.sub!("'","\\'") unless monster_name.nil?

      if @db.fetch("select mid from Monster where Raid_rid=#{raid_rid} and name='#{monster_name}'").first.nil?
        sql = "INSERT INTO Monster (Raid_rid, name) VALUES (#{raid_rid}, '#{monster_name}');\n"
        ret << sql
        @db.execute(sql)
      else
        ret << "-- Monster #{monster_name} is in the DB, skipping...\n"
      end

      monster_mid = @db.fetch("select mid from Monster where Raid_rid=#{raid_rid} and name='#{monster_name}'").first[:mid]

      if @db.fetch("select * from Monster_has_Item where Monster_mid=#{monster_mid} and Item_iid=#{iid}").first.nil?
        sql = "INSERT INTO Monster_has_Item (Monster_mid, Item_iid) VALUES (#{monster_mid}, #{iid});\n"
        ret << sql
        @db.execute(sql)
      else
        ret << "-- Monster+Item #{monster_name}+#{iid} is in the DB, skipping...\n"
      end

      # return it as a string
      return ret
    else
      # just return a comment
      return "-- Item #{iid} is in the DB, skipping...\n"
    end
  end
end


# This code is executed only if this file itself is being executed.
if $0 == __FILE__
  # Create a new instance for a WoW characer
  wowdb = WoWDB.new("Watermaker", "Aggramar")

  # Create the DB schema if it doesn't yet exist
  wowdb.create_database

  # Generate insert statements for the character
  insert_statements = wowdb.generate_insert_statements!

  # Print the insert statements to stdout
  puts insert_statements
end
